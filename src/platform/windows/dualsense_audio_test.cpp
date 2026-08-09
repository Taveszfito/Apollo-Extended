/**
 * @file src/platform/windows/dualsense_audio_test.cpp
 * @brief Explicit diagnostics and test routing for the virtual DualSense audio endpoint.
 */

#include "dualsense_audio.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cwctype>
#include <stop_token>
#include <string_view>
#include <thread>

#include <audioclient.h>
#include <avrt.h>
#include <cfgmgr32.h>
#include <functiondiscoverykeys_devpkey.h>
#include <mmdeviceapi.h>
#include <windows.h>

#include "src/logging.h"

namespace platf::dualsense_audio {
  namespace {
    constexpr GUID apollo_dualsense_container_id {
      0xd5e054c0, 0x0ce6, 0x4c00, {0xae, 0x50, 0x41, 0x50, 0x4f, 0x4c, 0x4c, 0x4f}
    };

    template<class T>
    class com_ptr_t {
    public:
      ~com_ptr_t() { reset(); }
      T **put() {
        reset();
        return &value_;
      }
      void reset() {
        if (value_) value_->Release();
        value_ = nullptr;
      }
      T *get() const { return value_; }
      T *operator->() const { return value_; }
      explicit operator bool() const { return value_ != nullptr; }

    private:
      T *value_ = nullptr;
    };

    class com_scope_t {
    public:
      com_scope_t(): status_(CoInitializeEx(nullptr, COINIT_MULTITHREADED)) {}
      ~com_scope_t() {
        if (SUCCEEDED(status_)) CoUninitialize();
      }
      bool valid() const { return SUCCEEDED(status_) || status_ == RPC_E_CHANGED_MODE; }

    private:
      HRESULT status_;
    };

    bool contains_case_insensitive(std::wstring_view text, std::wstring_view wanted) {
      return std::search(
               text.begin(), text.end(), wanted.begin(), wanted.end(),
               [](wchar_t left, wchar_t right) { return std::towlower(left) == std::towlower(right); }
             ) != text.end();
    }

    std::string to_utf8(std::wstring_view text) {
      if (text.empty()) return {};
      const auto size = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
      std::string result(size, '\0');
      WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), result.data(), size, nullptr, nullptr);
      return result;
    }

    std::wstring parent_instance_id(IMMDevice *device) {
      LPWSTR endpoint_id = nullptr;
      if (FAILED(device->GetId(&endpoint_id)) || !endpoint_id) return {};
      std::wstring instance_id = L"SWD\\MMDEVAPI\\";
      instance_id += endpoint_id;
      CoTaskMemFree(endpoint_id);
      DEVINST endpoint_node = 0;
      if (CM_Locate_DevNodeW(&endpoint_node, instance_id.data(), CM_LOCATE_DEVNODE_NORMAL) != CR_SUCCESS) return {};
      DEVINST parent_node = 0;
      if (CM_Get_Parent(&parent_node, endpoint_node, 0) != CR_SUCCESS) return {};
      std::array<wchar_t, MAX_DEVICE_ID_LEN> parent_id {};
      if (CM_Get_Device_IDW(parent_node, parent_id.data(), static_cast<ULONG>(parent_id.size()), 0) != CR_SUCCESS) return {};
      return parent_id.data();
    }

    bool is_target(IMMDevice *device, std::wstring *friendly_name = nullptr) {
      com_ptr_t<IPropertyStore> properties;
      if (FAILED(device->OpenPropertyStore(STGM_READ, properties.put()))) return false;
      PROPVARIANT name;
      PropVariantInit(&name);
      const auto name_status = properties->GetValue(PKEY_Device_FriendlyName, &name);
      const auto has_name = SUCCEEDED(name_status) && name.vt == VT_LPWSTR && name.pwszVal;

      PROPVARIANT container_id;
      PropVariantInit(&container_id);
      const auto container_status = properties->GetValue(PKEY_Device_ContainerId, &container_id);
      const auto container_matches = SUCCEEDED(container_status) && container_id.vt == VT_CLSID &&
                                     container_id.puuid != nullptr &&
                                     IsEqualGUID(*container_id.puuid, apollo_dualsense_container_id);
      PropVariantClear(&container_id);

      const auto root_audio = contains_case_insensitive(parent_instance_id(device), L"ROOT\\MEDIA");
      const auto name_matches = has_name && contains_case_insensitive(name.pwszVal, L"Apollo Extended DualSense Audio");
      const auto matches = container_matches || name_matches || root_audio;
      if (matches && friendly_name && has_name) *friendly_name = name.pwszVal;
      PropVariantClear(&name);
      return matches;
    }

    IMMDevice *find_target(IMMDeviceEnumerator *enumerator, std::wstring *friendly_name = nullptr) {
      com_ptr_t<IMMDeviceCollection> devices;
      if (FAILED(enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, devices.put()))) return nullptr;
      UINT count = 0;
      devices->GetCount(&count);
      for (UINT index = 0; index < count; ++index) {
        IMMDevice *device = nullptr;
        if (SUCCEEDED(devices->Item(index, &device)) && device) {
          if (is_target(device, friendly_name)) return device;
          device->Release();
        }
      }
      return nullptr;
    }

    IMMDevice *find_mirror_source(IMMDeviceEnumerator *enumerator) {
      // A newly created controller endpoint can temporarily become Windows'
      // default render device. Never loop it back into itself. Prefer the
      // normal defaults, then fall back to any active non-controller output.
      for (const auto role : {eConsole, eMultimedia, eCommunications}) {
        IMMDevice *device = nullptr;
        if (SUCCEEDED(enumerator->GetDefaultAudioEndpoint(eRender, role, &device)) && device) {
          if (!is_target(device)) return device;
          device->Release();
        }
      }

      com_ptr_t<IMMDeviceCollection> devices;
      if (FAILED(enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, devices.put()))) return nullptr;
      UINT count = 0;
      devices->GetCount(&count);
      for (UINT index = 0; index < count; ++index) {
        IMMDevice *device = nullptr;
        if (SUCCEEDED(devices->Item(index, &device)) && device) {
          if (!is_target(device)) return device;
          device->Release();
        }
      }
      return nullptr;
    }

    std::wstring device_id(IMMDevice *device) {
      if (!device) return {};
      LPWSTR raw_id = nullptr;
      if (FAILED(device->GetId(&raw_id)) || !raw_id) return {};
      std::wstring id {raw_id};
      CoTaskMemFree(raw_id);
      return id;
    }

    WAVEFORMATEXTENSIBLE quad_pcm_format() {
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
      return format;
    }

    WAVEFORMATEXTENSIBLE stereo_float_format() {
      WAVEFORMATEXTENSIBLE format {};
      format.Format.wFormatTag = WAVE_FORMAT_EXTENSIBLE;
      format.Format.nChannels = 2;
      format.Format.nSamplesPerSec = sample_rate;
      format.Format.wBitsPerSample = 32;
      format.Format.nBlockAlign = 8;
      format.Format.nAvgBytesPerSec = sample_rate * 8;
      format.Format.cbSize = sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX);
      format.Samples.wValidBitsPerSample = 32;
      format.dwChannelMask = SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT;
      format.SubFormat = KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;
      return format;
    }

    int open_quad_renderer(IMMDevice *device, com_ptr_t<IAudioClient> &client,
                           com_ptr_t<IAudioRenderClient> &renderer, UINT32 &buffer_frames) {
      auto status = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                                     reinterpret_cast<void **>(client.put()));
      if (FAILED(status)) return -10;
      auto format = quad_pcm_format();
      status = client->Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_NOPERSIST,
                                  1000000, 0, reinterpret_cast<WAVEFORMATEX *>(&format), nullptr);
      if (FAILED(status)) return -11;
      if (FAILED(client->GetBufferSize(&buffer_frames))) return -12;
      if (FAILED(client->GetService(__uuidof(IAudioRenderClient), reinterpret_cast<void **>(renderer.put())))) return -13;
      return 0;
    }

    std::jthread mirror_thread;
    std::atomic_bool mirror_active {false};
    std::atomic_int mirror_result {0};

    int mirror_session(std::stop_token stop) {
      com_scope_t com;
      if (!com.valid()) return -20;
      com_ptr_t<IMMDeviceEnumerator> enumerator;
      if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                                  __uuidof(IMMDeviceEnumerator), reinterpret_cast<void **>(enumerator.put())))) return -21;

      com_ptr_t<IMMDevice> source;
      *source.put() = find_mirror_source(enumerator.get());
      if (!source) return -22;
      const auto source_id = device_id(source.get());
      com_ptr_t<IMMDevice> target;
      *target.put() = find_target(enumerator.get());
      if (!target) return -23;

      com_ptr_t<IAudioClient> capture_client;
      if (FAILED(source->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                                  reinterpret_cast<void **>(capture_client.put())))) return -24;
      auto capture_format = stereo_float_format();
      constexpr DWORD capture_flags = AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_EVENTCALLBACK |
                                      AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY |
                                      AUDCLNT_STREAMFLAGS_NOPERSIST;
      if (FAILED(capture_client->Initialize(AUDCLNT_SHAREMODE_SHARED, capture_flags, 100000, 0,
                                            reinterpret_cast<WAVEFORMATEX *>(&capture_format), nullptr))) return -25;

      const auto event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
      if (!event || FAILED(capture_client->SetEventHandle(event))) {
        if (event) CloseHandle(event);
        return -26;
      }
      com_ptr_t<IAudioCaptureClient> capture;
      if (FAILED(capture_client->GetService(__uuidof(IAudioCaptureClient), reinterpret_cast<void **>(capture.put())))) {
        CloseHandle(event);
        return -27;
      }

      com_ptr_t<IAudioClient> render_client;
      com_ptr_t<IAudioRenderClient> render;
      UINT32 render_frames = 0;
      const auto render_result = open_quad_renderer(target.get(), render_client, render, render_frames);
      if (render_result != 0) {
        CloseHandle(event);
        return render_result;
      }

      if (FAILED(render_client->Start()) || FAILED(capture_client->Start())) {
        CloseHandle(event);
        return -28;
      }
      mirror_active.store(true, std::memory_order_release);
      BOOST_LOG(info) << "DualSense test mirror active: Windows stereo duplicated to all four controller channels";

      int result = 0;
      auto next_source_check = std::chrono::steady_clock::now() + std::chrono::milliseconds(250);
      while (!stop.stop_requested()) {
        const auto wait = WaitForSingleObject(event, 50);
        if (std::chrono::steady_clock::now() >= next_source_check) {
          next_source_check = std::chrono::steady_clock::now() + std::chrono::milliseconds(250);
          com_ptr_t<IMMDevice> current_source;
          *current_source.put() = find_mirror_source(enumerator.get());
          if (!current_source || device_id(current_source.get()) != source_id) {
            result = 1;  // Windows changed its active output; reopen loopback on the new endpoint.
            break;
          }
        }
        if (wait == WAIT_TIMEOUT) continue;
        if (wait != WAIT_OBJECT_0) {
          result = -29;
          break;
        }

        UINT32 next_frames = 0;
        while (!stop.stop_requested() && SUCCEEDED(capture->GetNextPacketSize(&next_frames)) && next_frames > 0) {
          BYTE *source_data = nullptr;
          UINT32 source_frames = 0;
          DWORD flags = 0;
          auto status = capture->GetBuffer(&source_data, &source_frames, &flags, nullptr, nullptr);
          if (FAILED(status)) {
            result = status == AUDCLNT_E_DEVICE_INVALIDATED ? -30 : -31;
            break;
          }

          UINT32 padding = 0;
          render_client->GetCurrentPadding(&padding);
          const auto frames_to_write = std::min(source_frames, render_frames - std::min(render_frames, padding));
          if (frames_to_write > 0) {
            BYTE *target_data = nullptr;
            if (SUCCEEDED(render->GetBuffer(frames_to_write, &target_data))) {
              auto *output = reinterpret_cast<std::int16_t *>(target_data);
              const auto *input = reinterpret_cast<const float *>(source_data);
              for (UINT32 frame = 0; frame < frames_to_write; ++frame) {
                const auto left = (flags & AUDCLNT_BUFFERFLAGS_SILENT) || !input ? 0.0f : input[frame * 2];
                const auto right = (flags & AUDCLNT_BUFFERFLAGS_SILENT) || !input ? 0.0f : input[frame * 2 + 1];
                const auto left_s16 = static_cast<std::int16_t>(std::clamp(left, -1.0f, 1.0f) * 32767.0f);
                const auto right_s16 = static_cast<std::int16_t>(std::clamp(right, -1.0f, 1.0f) * 32767.0f);
                output[frame * 4] = left_s16;
                output[frame * 4 + 1] = right_s16;
                output[frame * 4 + 2] = left_s16;
                output[frame * 4 + 3] = right_s16;
              }
              render->ReleaseBuffer(frames_to_write, 0);
            }
          }
          capture->ReleaseBuffer(source_frames);
          if (result != 0) break;
        }
        if (result != 0) break;
      }

      capture_client->Stop();
      render_client->Stop();
      CloseHandle(event);
      return result;
    }

    int mirror_loop(std::stop_token stop) {
      int result = 0;
      do {
        result = mirror_session(stop);
        if (result == 1 && !stop.stop_requested()) {
          BOOST_LOG(info) << "Windows default audio output changed; reopening DualSense test mirror";
        }
      } while (result == 1 && !stop.stop_requested());

      mirror_active.store(false, std::memory_order_release);
      BOOST_LOG(info) << "DualSense test mirror stopped with result " << (result == 1 ? 0 : result);
      return result == 1 ? 0 : result;
    }
  }  // namespace

  endpoint_info_t endpoint_info() {
    endpoint_info_t info;
    com_scope_t com;
    if (!com.valid()) return info;
    com_ptr_t<IMMDeviceEnumerator> enumerator;
    if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                                __uuidof(IMMDeviceEnumerator), reinterpret_cast<void **>(enumerator.put())))) return info;
    com_ptr_t<IMMDevice> endpoint;
    std::wstring name;
    *endpoint.put() = find_target(enumerator.get(), &name);
    if (!endpoint) return info;

    info.present = true;
    info.name = to_utf8(name);
    LPWSTR id = nullptr;
    if (SUCCEEDED(endpoint->GetId(&id)) && id) {
      info.id = to_utf8(id);
      CoTaskMemFree(id);
    }
    com_ptr_t<IAudioClient> client;
    if (SUCCEEDED(endpoint->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                                     reinterpret_cast<void **>(client.put())))) {
      WAVEFORMATEX *format = nullptr;
      if (SUCCEEDED(client->GetMixFormat(&format)) && format) {
        info.quadraphonic = format->nChannels == channel_count && format->nSamplesPerSec == sample_rate;
        CoTaskMemFree(format);
      }
    }
    return info;
  }

  int play_test_tone(int channel, std::uint32_t duration_ms) {
    if (channel < -1 || channel >= channel_count || duration_ms < 100 || duration_ms > 10000) return -1;
    com_scope_t com;
    if (!com.valid()) return -2;
    com_ptr_t<IMMDeviceEnumerator> enumerator;
    if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                                __uuidof(IMMDeviceEnumerator), reinterpret_cast<void **>(enumerator.put())))) return -3;
    com_ptr_t<IMMDevice> endpoint;
    *endpoint.put() = find_target(enumerator.get());
    if (!endpoint) return -4;

    com_ptr_t<IAudioClient> client;
    com_ptr_t<IAudioRenderClient> render;
    UINT32 buffer_frames = 0;
    const auto open_result = open_quad_renderer(endpoint.get(), client, render, buffer_frames);
    if (open_result != 0) return open_result;
    if (FAILED(client->Start())) return -5;

    const std::array<double, 4> frequencies {440.0, 660.0, 90.0, 140.0};
    std::uint64_t frame_index = 0;
    const auto total_frames = static_cast<std::uint64_t>(sample_rate) * duration_ms / 1000;
    while (frame_index < total_frames) {
      UINT32 padding = 0;
      client->GetCurrentPadding(&padding);
      auto available = buffer_frames - std::min(buffer_frames, padding);
      available = static_cast<UINT32>(std::min<std::uint64_t>(available, total_frames - frame_index));
      if (!available) {
        Sleep(2);
        continue;
      }
      BYTE *raw = nullptr;
      if (FAILED(render->GetBuffer(available, &raw))) break;
      auto *samples = reinterpret_cast<std::int16_t *>(raw);
      for (UINT32 frame = 0; frame < available; ++frame, ++frame_index) {
        for (int output_channel = 0; output_channel < channel_count; ++output_channel) {
          const auto selected = channel == -1 || channel == output_channel;
          const auto amplitude = output_channel < 2 ? 3500.0 : 9000.0;
          const auto time = static_cast<double>(frame_index) / sample_rate;
          samples[frame * channel_count + output_channel] = selected ? static_cast<std::int16_t>(
            amplitude * std::sin(2.0 * 3.141592653589793 * frequencies[output_channel] * time)
          ) : 0;
        }
      }
      if (FAILED(render->ReleaseBuffer(available, 0))) break;
    }
    Sleep(100);
    client->Stop();
    BOOST_LOG(info) << "DualSense channel test completed for channel " << channel;
    return 0;
  }

  int set_system_audio_mirror(bool enabled) {
    if (!enabled) {
      if (mirror_thread.joinable()) {
        mirror_thread.request_stop();
        mirror_thread.join();
      }
      mirror_active.store(false, std::memory_order_release);
      return 0;
    }
    if (mirror_active.load(std::memory_order_acquire)) return 0;
    if (mirror_thread.joinable()) {
      mirror_thread.request_stop();
      mirror_thread.join();
    }
    mirror_result.store(0, std::memory_order_release);
    mirror_thread = std::jthread {[](std::stop_token stop) {
      const auto result = mirror_loop(stop);
      mirror_result.store(result, std::memory_order_release);
      if (result != 0) {
        BOOST_LOG(error) << "DualSense test mirror failed with result " << result;
      }
    }};
    return 0;
  }

  bool system_audio_mirror_active() {
    return mirror_active.load(std::memory_order_acquire);
  }

  int system_audio_mirror_result() {
    return mirror_result.load(std::memory_order_acquire);
  }

  int restart_endpoint() {
    set_system_audio_mirror(false);
    request_capture_restart();
    // Give the stream worker time to release and reacquire WASAPI, then wake
    // the refreshed path with a short signal on all four controller channels.
    Sleep(1200);
    const auto result = play_test_tone(-1, 180);
    BOOST_LOG(result == 0 ? info : warning) << "DualSense audio pipeline reset result: " << result;
    return result;
  }
}  // namespace platf::dualsense_audio
