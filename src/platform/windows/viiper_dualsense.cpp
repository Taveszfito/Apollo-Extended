/**
 * @file src/platform/windows/viiper_dualsense.cpp
 * @brief VIIPER V5-backed native USB DualSense device.
 */

#include "viiper_dualsense.h"

#include <winsock2.h>
#include <ws2tcpip.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <mutex>
#include <regex>
#include <set>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include "src/logging.h"

namespace platf::viiper_dualsense {
  namespace {
    constexpr std::uint16_t api_port = 3242;
    constexpr std::size_t input_state_size = 33;
    constexpr std::size_t frame_header_size = 16;
    constexpr std::size_t output_state_size = 474;
    constexpr std::size_t raw_output_offset = 28;
    constexpr std::size_t raw_output_size = 48;

    class winsock_t {
    public:
      winsock_t() {
        available_ = WSAStartup(MAKEWORD(2, 2), &data_) == 0;
      }
      ~winsock_t() {
        if (available_) WSACleanup();
      }
      bool available() const { return available_; }

    private:
      WSADATA data_ {};
      bool available_ = false;
    };

    winsock_t &winsock() {
      static winsock_t instance;
      return instance;
    }

    SOCKET connect_api() {
      if (!winsock().available()) return INVALID_SOCKET;
      const auto socket_handle = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
      if (socket_handle == INVALID_SOCKET) return INVALID_SOCKET;
      sockaddr_in address {};
      address.sin_family = AF_INET;
      address.sin_port = htons(api_port);
      inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
      if (connect(socket_handle, reinterpret_cast<sockaddr *>(&address), sizeof(address)) != 0) {
        closesocket(socket_handle);
        return INVALID_SOCKET;
      }
      BOOL no_delay = TRUE;
      setsockopt(socket_handle, IPPROTO_TCP, TCP_NODELAY,
                 reinterpret_cast<const char *>(&no_delay), sizeof(no_delay));
      return socket_handle;
    }

    bool send_all(SOCKET socket_handle, const std::uint8_t *data, std::size_t size) {
      while (size != 0) {
        const auto sent = send(socket_handle, reinterpret_cast<const char *>(data),
                               static_cast<int>(size), 0);
        if (sent <= 0) return false;
        data += sent;
        size -= static_cast<std::size_t>(sent);
      }
      return true;
    }

    std::string request(const std::string &text) {
      const auto socket_handle = connect_api();
      if (socket_handle == INVALID_SOCKET) return {};
      std::vector<std::uint8_t> payload(text.begin(), text.end());
      payload.push_back(0);
      if (!send_all(socket_handle, payload.data(), payload.size())) {
        closesocket(socket_handle);
        return {};
      }
      shutdown(socket_handle, SD_SEND);
      std::string response;
      std::array<char, 4096> buffer {};
      for (;;) {
        const auto received = recv(socket_handle, buffer.data(), static_cast<int>(buffer.size()), 0);
        if (received <= 0) break;
        response.append(buffer.data(), static_cast<std::size_t>(received));
      }
      closesocket(socket_handle);
      return response;
    }

    std::string usbip_path() {
      std::array<char, MAX_PATH> program_files {};
      const auto length = GetEnvironmentVariableA("ProgramW6432", program_files.data(),
                                                  static_cast<DWORD>(program_files.size()));
      const std::string root = length > 0 && length < program_files.size() ?
        std::string {program_files.data(), length} : "C:\\Program Files";
      return root + "\\USBip\\usbip.exe";
    }

    std::string run_command(const std::string &command) {
      std::string output;
      if (auto *pipe = _popen(command.c_str(), "r")) {
        std::array<char, 1024> buffer {};
        while (std::fgets(buffer.data(), static_cast<int>(buffer.size()), pipe)) output += buffer.data();
        _pclose(pipe);
      }
      return output;
    }

    std::uint32_t crc32(const std::uint8_t *data, std::size_t size, std::uint32_t crc = 0) {
      crc ^= 0xFFFFFFFFU;
      while (size-- != 0) {
        crc ^= *data++;
        for (int bit = 0; bit < 8; ++bit) {
          crc = (crc >> 1U) ^ (0xEDB88320U & (0U - (crc & 1U)));
        }
      }
      return crc ^ 0xFFFFFFFFU;
    }

    void put_u16(std::uint8_t *target, std::uint16_t value) {
      target[0] = static_cast<std::uint8_t>(value);
      target[1] = static_cast<std::uint8_t>(value >> 8U);
    }

    void put_u32(std::uint8_t *target, std::uint32_t value) {
      for (int index = 0; index < 4; ++index) {
        target[index] = static_cast<std::uint8_t>(value >> (index * 8));
      }
    }

    std::uint16_t get_u16(const std::uint8_t *source) {
      return static_cast<std::uint16_t>(source[0] | (source[1] << 8U));
    }

    bool receive_exact(SOCKET socket_handle, std::uint8_t *data, std::size_t size) {
      while (size != 0) {
        const auto received = recv(socket_handle, reinterpret_cast<char *>(data),
                                   static_cast<int>(size), 0);
        if (received <= 0) return false;
        data += received;
        size -= static_cast<std::size_t>(received);
      }
      return true;
    }

    std::int8_t axis_i8(std::int32_t value) {
      if (value < 0) return static_cast<std::int8_t>(std::max(-128, value / 256));
      return static_cast<std::int8_t>(std::min(127, value / 258));
    }

    std::int16_t scaled_i16(float value, float scale) {
      const auto scaled = std::lround(value * scale);
      return static_cast<std::int16_t>(std::clamp<long>(scaled, -32768, 32767));
    }

    class device_impl_t final: public device_t {
    public:
      explicit device_impl_t(output_callback_t callback): callback_ {std::move(callback)} {
        // Both touch contacts must start released. A zero-initialized contact
        // byte means an active finger with tracking ID 0 in Sony's format.
        state_[15] = 0x80;
        state_[20] = 0x80;
        put_u16(state_.data() + 31, static_cast<std::uint16_t>(-8192));
      }

      bool initialize() {
        auto buses = request("bus/list");
        std::smatch match;
        if (std::regex_search(buses, match, std::regex {R"("buses"\s*:\s*\[\s*(\d+))"})) {
          bus_id_ = static_cast<std::uint32_t>(std::stoul(match[1].str()));
          owns_bus_ = false;
        } else {
          const auto created = request("bus/create 0");
          if (!std::regex_search(created, match, std::regex {R"("busId"\s*:\s*(\d+))"})) {
            BOOST_LOG(warning) << "VIIPER bus creation failed: " << created;
            return false;
          }
          bus_id_ = static_cast<std::uint32_t>(std::stoul(match[1].str()));
          owns_bus_ = true;
        }

        const auto added = request(
          "bus/" + std::to_string(bus_id_) +
          "/add {\"type\":\"dualsensecombinedaudioduplexv5\"}"
        );
        if (!std::regex_search(added, match, std::regex {R"json("devId"\s*:\s*"([^"]+)")json"})) {
          BOOST_LOG(warning) << "VIIPER DualSense creation failed: " << added;
          cleanup_bus();
          return false;
        }
        device_id_ = match[1].str();

        stream_ = connect_api();
        if (stream_ == INVALID_SOCKET) {
          cleanup_device();
          return false;
        }
        const auto path = "bus/" + std::to_string(bus_id_) + "/" + device_id_;
        std::vector<std::uint8_t> handshake(path.begin(), path.end());
        handshake.push_back(0);
        if (!send_all(stream_, handshake.data(), handshake.size())) {
          closesocket(stream_);
          stream_ = INVALID_SOCKET;
          cleanup_device();
          return false;
        }

        running_ = true;
        reader_ = std::thread {[this] { read_feedback(); }};
        BOOST_LOG(info) << "VIIPER native USB DualSense created on bus " << bus_id_
                        << " device " << device_id_;
        return submit_state();
      }

      ~device_impl_t() override {
        running_ = false;
        if (stream_ != INVALID_SOCKET) {
          shutdown(stream_, SD_BOTH);
          closesocket(stream_);
          stream_ = INVALID_SOCKET;
        }
        if (reader_.joinable()) reader_.join();
        cleanup_device();
      }

      bool set_gamepad(std::int16_t lx, std::int16_t ly, std::int16_t rx, std::int16_t ry,
                       std::uint32_t buttons, std::uint8_t dpad,
                       std::uint8_t l2, std::uint8_t r2) override {
        {
          auto lock = std::lock_guard {state_mutex_};
          state_[0] = static_cast<std::uint8_t>(axis_i8(lx));
          state_[1] = static_cast<std::uint8_t>(axis_i8(-static_cast<std::int32_t>(ly)));
          state_[2] = static_cast<std::uint8_t>(axis_i8(rx));
          state_[3] = static_cast<std::uint8_t>(axis_i8(-static_cast<std::int32_t>(ry)));
          put_u32(state_.data() + 4, buttons);
          state_[8] = dpad;
          state_[9] = l2;
          state_[10] = r2;
        }
        return submit_state();
      }

      bool set_touch(std::size_t slot, bool active, std::uint16_t x,
                     std::uint16_t y, std::uint8_t tracking_id) override {
        if (slot >= 2) return false;
        {
          auto lock = std::lock_guard {state_mutex_};
          const auto offset = slot == 0 ? 11U : 16U;
          put_u16(state_.data() + offset, x);
          put_u16(state_.data() + offset + 2U, y);
          // DualSense uses bit 7 as the *inactive* flag. The previous encoding
          // set it for active contacts, which made an idle pad appear touched
          // at (0, 0) and hid the contact as soon as a finger was placed.
          state_[offset + 4U] = active ?
            static_cast<std::uint8_t>(tracking_id & 0x7FU) :
            static_cast<std::uint8_t>(0x80U | (tracking_id & 0x7FU));
        }
        return submit_state();
      }

      bool set_motion(bool gyroscope, float x, float y, float z) override {
        {
          auto lock = std::lock_guard {state_mutex_};
          const auto offset = gyroscope ? 21U : 27U;
          const auto scale = gyroscope ? 16.384F : (8192.0F / 9.80665F);
          put_u16(state_.data() + offset, static_cast<std::uint16_t>(scaled_i16(x, scale)));
          put_u16(state_.data() + offset + 2U, static_cast<std::uint16_t>(scaled_i16(y, scale)));
          put_u16(state_.data() + offset + 4U, static_cast<std::uint16_t>(scaled_i16(z, scale)));
        }
        return submit_state();
      }

    private:
      bool submit_state() {
        if (!running_ || stream_ == INVALID_SOCKET) return false;
        std::array<std::uint8_t, input_state_size> state;
        {
          auto lock = std::lock_guard {state_mutex_};
          state = state_;
        }

        std::array<std::uint8_t, frame_header_size + input_state_size> frame {};
        frame[0] = 'V'; frame[1] = 'P'; frame[2] = 'C'; frame[3] = 'M';
        frame[4] = 5;
        frame[5] = 1;
        put_u16(frame.data() + 6, static_cast<std::uint16_t>(state.size()));
        const auto sequence = sequence_.fetch_add(1, std::memory_order_relaxed);
        put_u32(frame.data() + 8, sequence);
        std::copy(state.begin(), state.end(), frame.begin() + frame_header_size);
        auto crc = crc32(frame.data() + 4, 8);
        crc = crc32(state.data(), state.size(), crc);
        put_u32(frame.data() + 12, crc);

        auto lock = std::lock_guard {send_mutex_};
        const auto sent = send_all(stream_, frame.data(), frame.size());
        if (!sent) running_ = false;
        return sent;
      }

      void read_feedback() {
        std::array<std::uint8_t, raw_output_size> last_raw {};
        bool has_last_raw = false;
        while (running_) {
          std::array<std::uint8_t, frame_header_size> header {};
          if (!receive_exact(stream_, header.data(), header.size())) break;
          if (header[0] != 'V' || header[1] != 'P' || header[2] != 'C' ||
              header[3] != 'M' || header[4] != 5) break;
          const auto payload_size = get_u16(header.data() + 6);
          std::vector<std::uint8_t> payload(payload_size);
          if (!receive_exact(stream_, payload.data(), payload.size())) break;

          std::span<const std::uint8_t> feedback;
          if (header[5] == 0x81 && payload.size() >= output_state_size) {
            feedback = {payload.data(), output_state_size};
          } else if (header[5] == 0x83 && payload.size() >= 2 + output_state_size &&
                     get_u16(payload.data()) == output_state_size) {
            feedback = {payload.data() + 2, output_state_size};
          } else {
            continue;
          }

          std::array<std::uint8_t, raw_output_size> raw {};
          std::copy_n(feedback.begin() + raw_output_offset, raw.size(), raw.begin());
          if (!has_last_raw || raw != last_raw) {
            last_raw = raw;
            has_last_raw = true;
            if (callback_) callback_(raw);
          }
        }
        running_ = false;
      }

      void cleanup_device() {
        if (!device_id_.empty()) {
          request("bus/" + std::to_string(bus_id_) + "/remove " + device_id_);
          device_id_.clear();
        }
        cleanup_bus();
      }

      void cleanup_bus() {
        if (owns_bus_ && bus_id_ != 0) {
          request("bus/remove " + std::to_string(bus_id_));
          owns_bus_ = false;
        }
      }

      output_callback_t callback_;
      SOCKET stream_ = INVALID_SOCKET;
      std::thread reader_;
      std::atomic_bool running_ {false};
      std::atomic_uint32_t sequence_ {};
      std::mutex send_mutex_;
      std::mutex state_mutex_;
      std::array<std::uint8_t, input_state_size> state_ {};
      std::uint32_t bus_id_ = 0;
      std::string device_id_;
      bool owns_bus_ = false;
    };
  }  // namespace

  std::unique_ptr<device_t> create(output_callback_t callback) {
    auto result = std::make_unique<device_impl_t>(std::move(callback));
    if (!result->initialize()) return {};
    return result;
  }

  bool runtime_available() {
    return request("ping").find("VIIPER") != std::string::npos;
  }

  void cleanup_orphaned_devices() {
    const auto executable = usbip_path();
    const auto listing = run_command('"' + executable + "\" port 2>&1");
    const std::regex port_header {R"(^Port\s+([0-9]+):)"};
    std::set<std::string> orphaned_ports;
    std::istringstream lines {listing};
    std::string line;
    std::string current_port;
    bool dualsense = false;
    bool local_viiper = false;
    const auto finish_entry = [&] {
      if (!current_port.empty() && dualsense && local_viiper) orphaned_ports.insert(current_port);
    };
    while (std::getline(lines, line)) {
      std::smatch match;
      if (std::regex_search(line, match, port_header)) {
        finish_entry();
        current_port = match[1].str();
        dualsense = false;
        local_viiper = false;
      } else if (!current_port.empty()) {
        dualsense = dualsense || line.find("(054c:0ce6)") != std::string::npos;
        local_viiper = local_viiper || line.find("usbip://localhost:3241/") != std::string::npos;
      }
    }
    finish_entry();

    for (const auto &port : orphaned_ports) {
      BOOST_LOG(warning) << "Removing orphaned VIIPER DualSense from usbip port " << port;
      const auto result = std::system(('"' + executable + "\" detach -p " + port + " >nul 2>&1").c_str());
      if (result != 0) {
        BOOST_LOG(warning) << "Could not detach orphaned VIIPER DualSense from usbip port " << port
                           << " (exit " << result << ')';
      }
    }
  }
}  // namespace platf::viiper_dualsense
