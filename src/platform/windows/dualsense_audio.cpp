/**
 * @file src/platform/windows/dualsense_audio.cpp
 * @brief WASAPI loopback capture for the virtual DualSense audio endpoint.
 */

#include "dualsense_audio.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cwctype>
#include <cstring>
#include <string_view>
#include <vector>

#include <audioclient.h>
#include <avrt.h>
#include <functiondiscoverykeys_devpkey.h>
#include <mmdeviceapi.h>
#include <windows.h>

#include "src/logging.h"

using namespace std::literals;

namespace platf::dualsense_audio {
  namespace {
    template<class T>
    class com_ptr_t {
    public:
      ~com_ptr_t() {
        if (value_) value_->Release();
      }

      T **put() {
        if (value_) {
          value_->Release();
          value_ = nullptr;
        }
        return &value_;
      }

      T *get() const { return value_; }
      T *operator->() const { return value_; }
      explicit operator bool() const { return value_ != nullptr; }

    private:
      T *value_ = nullptr;
    };

    struct handle_t {
      HANDLE value = nullptr;
      ~handle_t() {
        if (value) CloseHandle(value);
      }
    };

    bool contains_case_insensitive(std::wstring_view text, std::wstring_view wanted) {
      return std::search(
               text.begin(), text.end(), wanted.begin(), wanted.end(),
               [](wchar_t left, wchar_t right) { return std::towlower(left) == std::towlower(right); }
             ) != text.end();
    }

    bool is_apollo_dualsense_endpoint(IMMDevice *device) {
      com_ptr_t<IPropertyStore> properties;
      if (FAILED(device->OpenPropertyStore(STGM_READ, properties.put()))) return false;

      PROPVARIANT friendly_name;
      PropVariantInit(&friendly_name);
      const auto status = properties->GetValue(PKEY_Device_FriendlyName, &friendly_name);
      const auto matches = SUCCEEDED(status) && friendly_name.vt == VT_LPWSTR &&
                           friendly_name.pwszVal != nullptr &&
                           contains_case_insensitive(friendly_name.pwszVal, L"Apollo Extended DualSense Audio");
      PropVariantClear(&friendly_name);
      return matches;
    }

    IMMDevice *find_endpoint(IMMDeviceEnumerator *enumerator) {
      com_ptr_t<IMMDeviceCollection> endpoints;
      if (FAILED(enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, endpoints.put()))) return nullptr;

      UINT count = 0;
      if (FAILED(endpoints->GetCount(&count))) return nullptr;
      for (UINT index = 0; index < count; ++index) {
        IMMDevice *candidate = nullptr;
        if (SUCCEEDED(endpoints->Item(index, &candidate)) && candidate != nullptr) {
          if (is_apollo_dualsense_endpoint(candidate)) return candidate;
          candidate->Release();
        }
      }
      return nullptr;
    }
  }  // namespace

  int capture(std::atomic_bool &stop, const packet_callback_t &callback) {
    BOOST_LOG(info) << "DualSense audio WASAPI step: initialize COM";
    const auto com_status = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    const auto uninitialize_com = SUCCEEDED(com_status);
    if (FAILED(com_status) && com_status != RPC_E_CHANGED_MODE) {
      BOOST_LOG(error) << "DualSense audio capture could not initialize COM: 0x" << std::hex << com_status;
      return -1;
    }

    com_ptr_t<IMMDeviceEnumerator> enumerator;
    BOOST_LOG(info) << "DualSense audio WASAPI step: create endpoint enumerator";
    auto status = CoCreateInstance(
      __uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, __uuidof(IMMDeviceEnumerator),
      reinterpret_cast<void **>(enumerator.put())
    );
    if (FAILED(status)) {
      BOOST_LOG(error) << "DualSense audio capture could not create MMDevice enumerator: 0x" << std::hex << status;
      if (uninitialize_com) CoUninitialize();
      return -1;
    }

    com_ptr_t<IMMDevice> endpoint;
    BOOST_LOG(info) << "DualSense audio WASAPI step: enumerate render endpoints";
    *endpoint.put() = find_endpoint(enumerator.get());
    if (!endpoint) {
      BOOST_LOG(warning) << "Apollo Extended DualSense audio endpoint was not found";
      if (uninitialize_com) CoUninitialize();
      return -2;
    }

    com_ptr_t<IAudioClient> audio_client;
    BOOST_LOG(info) << "DualSense audio WASAPI step: activate audio client";
    status = endpoint->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, reinterpret_cast<void **>(audio_client.put()));
    if (FAILED(status)) {
      BOOST_LOG(error) << "DualSense audio capture could not activate endpoint: 0x" << std::hex << status;
      if (uninitialize_com) CoUninitialize();
      return -3;
    }

    WAVEFORMATEXTENSIBLE format {};
    format.Format.wFormatTag = WAVE_FORMAT_EXTENSIBLE;
    format.Format.nChannels = channel_count;
    format.Format.nSamplesPerSec = sample_rate;
    format.Format.wBitsPerSample = bits_per_sample;
    format.Format.nBlockAlign = bytes_per_frame;
    format.Format.nAvgBytesPerSec = sample_rate * bytes_per_frame;
    format.Format.cbSize = sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX);
    format.Samples.wValidBitsPerSample = bits_per_sample;
    format.dwChannelMask = KSAUDIO_SPEAKER_QUAD;
    format.SubFormat = KSDATAFORMAT_SUBTYPE_PCM;

    constexpr DWORD stream_flags = AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_EVENTCALLBACK |
                                   AUDCLNT_STREAMFLAGS_NOPERSIST;
    BOOST_LOG(info) << "DualSense audio WASAPI step: initialize quad loopback";
    status = audio_client->Initialize(
      AUDCLNT_SHAREMODE_SHARED, stream_flags, 100000, 0,
      reinterpret_cast<WAVEFORMATEX *>(&format), nullptr
    );
    if (FAILED(status)) {
      BOOST_LOG(error) << "DualSense audio endpoint rejected 48 kHz quad PCM: 0x" << std::hex << status;
      if (uninitialize_com) CoUninitialize();
      return -4;
    }

    BOOST_LOG(info) << "DualSense audio WASAPI step: create and register event";
    handle_t event {CreateEventW(nullptr, FALSE, FALSE, nullptr)};
    if (!event.value || FAILED(audio_client->SetEventHandle(event.value))) {
      BOOST_LOG(error) << "DualSense audio capture could not configure its event handle";
      if (uninitialize_com) CoUninitialize();
      return -5;
    }

    com_ptr_t<IAudioCaptureClient> capture_client;
    BOOST_LOG(info) << "DualSense audio WASAPI step: obtain capture client";
    status = audio_client->GetService(__uuidof(IAudioCaptureClient), reinterpret_cast<void **>(capture_client.put()));
    if (FAILED(status)) {
      BOOST_LOG(error) << "DualSense audio capture could not obtain IAudioCaptureClient: 0x" << std::hex << status;
      if (uninitialize_com) CoUninitialize();
      return -6;
    }

    DWORD task_index = 0;
    BOOST_LOG(info) << "DualSense audio WASAPI step: enter Pro Audio MMCSS";
    auto mmcss = AvSetMmThreadCharacteristicsW(L"Pro Audio", &task_index);
    BOOST_LOG(info) << "DualSense audio WASAPI step: start loopback";
    status = audio_client->Start();
    if (FAILED(status)) {
      BOOST_LOG(error) << "DualSense audio capture could not start: 0x" << std::hex << status;
      if (mmcss) AvRevertMmThreadCharacteristics(mmcss);
      if (uninitialize_com) CoUninitialize();
      return -7;
    }

    BOOST_LOG(info) << "DualSense audio capture active: 48000 Hz, 4 channels, 16-bit PCM";
    std::vector<std::uint8_t> pending;
    pending.reserve(bytes_per_packet * 3);
    int capture_result = 0;
    while (!stop.load(std::memory_order_acquire)) {
      const auto wait_status = WaitForSingleObject(event.value, 50);
      if (wait_status == WAIT_TIMEOUT) continue;
      if (wait_status != WAIT_OBJECT_0) break;

      UINT32 next_frames = 0;
      while (SUCCEEDED(capture_client->GetNextPacketSize(&next_frames)) && next_frames > 0) {
        BYTE *data = nullptr;
        UINT32 frames = 0;
        DWORD flags = 0;
        status = capture_client->GetBuffer(&data, &frames, &flags, nullptr, nullptr);
        if (status == AUDCLNT_E_DEVICE_INVALIDATED) {
          capture_result = -8;
          break;
        }
        if (FAILED(status)) break;

        const auto byte_count = static_cast<std::size_t>(frames) * bytes_per_frame;
        const auto old_size = pending.size();
        pending.resize(old_size + byte_count);
        if ((flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0 || data == nullptr) {
          std::fill(pending.begin() + old_size, pending.end(), 0);
        } else {
          std::memcpy(pending.data() + old_size, data, byte_count);
        }
        capture_client->ReleaseBuffer(frames);

        while (pending.size() >= bytes_per_packet) {
          callback(std::span<const std::uint8_t> {pending.data(), bytes_per_packet});
          pending.erase(pending.begin(), pending.begin() + bytes_per_packet);
        }
      }
      if (capture_result != 0) break;
    }

    audio_client->Stop();
    if (mmcss) AvRevertMmThreadCharacteristics(mmcss);
    if (uninitialize_com) CoUninitialize();
    BOOST_LOG(info) << "DualSense audio capture stopped";
    return capture_result;
  }
}  // namespace platf::dualsense_audio
