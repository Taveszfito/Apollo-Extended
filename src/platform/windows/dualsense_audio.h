/**
 * @file src/platform/windows/dualsense_audio.h
 * @brief Captures the virtual DualSense four-channel render stream.
 */
#pragma once

#include <atomic>
#include <cstdint>
#include <functional>
#include <span>
#include <string>

namespace platf::dualsense_audio {
  constexpr std::uint32_t sample_rate = 48000;
  constexpr std::uint16_t channel_count = 4;
  constexpr std::uint16_t bits_per_sample = 16;
  constexpr std::uint16_t frames_per_packet = 144;  // 3 ms at 48 kHz
  constexpr std::size_t bytes_per_frame = channel_count * bits_per_sample / 8;
  constexpr std::size_t bytes_per_packet = frames_per_packet * bytes_per_frame;

  using packet_callback_t = std::function<void(std::span<const std::uint8_t>)>;

  struct endpoint_info_t {
    bool present = false;
    bool quadraphonic = false;
    std::string id;
    std::string name;
  };

  /**
   * Capture 48 kHz, four-channel, signed 16-bit PCM from the Apollo Extended
   * virtual controller endpoint until stop is set. The callback always receives
   * complete three-millisecond packets.
   */
  int capture(std::atomic_bool &stop, const packet_callback_t &callback);

  /** Query the dedicated Apollo Extended controller render endpoint. */
  endpoint_info_t endpoint_info();

  /** Render a short tone to one channel (0-3) or all channels (-1). */
  int play_test_tone(int channel, std::uint32_t duration_ms = 1200);

  /** Duplicate the Windows default stereo output to both DualSense pairs. */
  int set_system_audio_mirror(bool enabled);
  bool system_audio_mirror_active();
  int system_audio_mirror_result();

  /** Ask an active capture worker to release and reacquire its WASAPI client. */
  void request_capture_restart();

  /** Reinitialize capture and render a short all-channel wake signal. */
  int restart_endpoint();
}  // namespace platf::dualsense_audio
