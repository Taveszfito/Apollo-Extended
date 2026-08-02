/**
 * @file src/controller_diagnostics.h
 * @brief Live Apollo Extended controller pipeline diagnostics.
 */
#pragma once

#include <atomic>
#include <chrono>
#include <cstdint>

namespace controller_diagnostics {
  inline std::atomic<std::uint64_t> client_packets {};
  inline std::atomic<std::int64_t> last_client_packet_ms {};
  inline std::atomic<std::uint32_t> last_buttons {};
  inline std::atomic<std::uint8_t> last_left_trigger {};
  inline std::atomic<std::uint8_t> last_right_trigger {};
  inline std::atomic<std::int16_t> last_left_x {};
  inline std::atomic<std::int16_t> last_left_y {};
  inline std::atomic<std::int16_t> last_right_x {};
  inline std::atomic<std::int16_t> last_right_y {};

  inline std::atomic<std::uint64_t> state_submit_attempts {};
  inline std::atomic<std::uint64_t> state_submit_successes {};
  inline std::atomic<std::uint64_t> state_submit_failures {};
  inline std::atomic<std::int64_t> last_state_submit_ms {};
  inline std::atomic<std::int64_t> last_state_submit_failure_ms {};

  inline std::atomic<std::uint64_t> output_reports {};
  inline std::atomic<std::int64_t> last_output_report_ms {};
  inline std::atomic<std::uint64_t> device_creates {};
  inline std::atomic<std::uint64_t> device_closes {};
  inline std::atomic<bool> device_present {};

  inline std::int64_t now_ms() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::steady_clock::now().time_since_epoch()).count();
  }

  inline void record_client_packet(std::uint32_t buttons, std::uint8_t left_trigger,
                                   std::uint8_t right_trigger, std::int16_t left_x,
                                   std::int16_t left_y, std::int16_t right_x,
                                   std::int16_t right_y) {
    last_buttons = buttons;
    last_left_trigger = left_trigger;
    last_right_trigger = right_trigger;
    last_left_x = left_x;
    last_left_y = left_y;
    last_right_x = right_x;
    last_right_y = right_y;
    last_client_packet_ms = now_ms();
    ++client_packets;
  }

  inline void record_state_submit(bool success) {
    last_state_submit_ms = now_ms();
    ++state_submit_attempts;
    if (success) {
      ++state_submit_successes;
    } else {
      last_state_submit_failure_ms = last_state_submit_ms.load();
      ++state_submit_failures;
    }
  }

  inline void record_output_report() {
    last_output_report_ms = now_ms();
    ++output_reports;
  }
}
