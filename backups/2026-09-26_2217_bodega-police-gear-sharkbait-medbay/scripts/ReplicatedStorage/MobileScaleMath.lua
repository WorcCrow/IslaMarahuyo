-- MobileScaleMath
-- Pure sizing math for shrinking desktop-pixel GUI panels to fit small / touch viewports.
-- Kept as a standalone module (no Instances touched) so the fit math can be checked
-- directly against real panel sizes instead of only by eyeballing a phone.

local M = {}

M.MARGIN = 16
M.MIN_SCALE = 0.55
M.TOUCH_CAP = 0.85

-- viewport / native: {X=, Y=} (a Vector2 works). native is the panel's size at Scale 1.
function M.fit(viewport, native, touch)
	if native.X <= 0 or native.Y <= 0 or viewport.X <= 0 or viewport.Y <= 0 then
		return 1
	end
	local safeW = viewport.X - M.MARGIN * 2
	local safeH = viewport.Y - M.MARGIN * 2
	local scale = math.min(safeW / native.X, safeH / native.Y, 1)
	if touch then
		scale = math.min(scale, M.TOUCH_CAP)
	end
	return math.max(scale, M.MIN_SCALE)
end

return M