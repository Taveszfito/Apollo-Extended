/**
 * @file src/platform/windows/dualsense_audio.h
 * @brief Captures the virtual DualSense four-channel render stream.
 */
#pragma once

#include <atomic>
#include <cstdint>
#include <functional>
#include <span>

namespace platf::dualsense_audio {
  constexpr std::uint32_t sample_rate = 48000;
  constexpr std::uint16_t channel_count = 4;
  constexpr std::uint16_t bits_per_sample = 16;
  constexpr std::uint16_t frames_per_packet = 144;  // 3 ms at 48 kHz
  constexpr std::size_t bytes_per_frame = channel_count * bits_per_sample / 8;
  constexpr std::size_t bytes_per_packet = frames_per_packet * bytes_per_frame;

  using packet_callback_t = std::function<void(std::span<const std::uint8_t>)>;

  /**
   * Capture 48 kHz, four-channel, signed 16-bit PCM from the Apollo Extended
   * virtual controller endpoint until stop is set. The callback always receives
   * complete three-millisecond packets.
   */
  int capture(std::atomic_bool &stop, const packet_callback_t &callback);
}  // namespace platf::dualsense_audio
