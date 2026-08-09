/**
 * @file src/platform/windows/viiper_dualsense.h
 * @brief VIIPER V5-backed native USB DualSense device.
 */
#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <span>

namespace platf::viiper_dualsense {
  using output_callback_t = std::function<void(std::span<const std::uint8_t>)>;

  class device_t {
  public:
    virtual ~device_t() = default;

    virtual bool set_gamepad(std::int16_t lx, std::int16_t ly, std::int16_t rx, std::int16_t ry,
                             std::uint32_t buttons, std::uint8_t dpad,
                             std::uint8_t l2, std::uint8_t r2) = 0;
    virtual bool set_touch(std::size_t slot, bool active, std::uint16_t x,
                           std::uint16_t y, std::uint8_t tracking_id) = 0;
    virtual bool set_motion(bool gyroscope, float x, float y, float z) = 0;
  };

  std::unique_ptr<device_t> create(output_callback_t callback);
  bool runtime_available();
  /** Remove abandoned localhost VIIPER DualSense imports from usbip-win2. */
  void cleanup_orphaned_devices();
}  // namespace platf::viiper_dualsense
