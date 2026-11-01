-- Scene Stash app icon: a tilted ticket stub caught in a projector beam.
-- Run: aseprite -b --script Design/build_logo.lua
local S = 1024
local spr = Sprite(S, S, ColorMode.RGB)
local gc = spr.cels[1].image.context
gc.antialias = true

-- GraphicsContext has no transforms, so ticket geometry goes through X().
local ox, oy, rot = 0, 0, 0
local function X(x, y)
  local c, sn = math.cos(rot), math.sin(rot)
  return ox + x * c - y * sn, oy + x * sn + y * c
end
local function M(x, y) gc:moveTo(X(x, y)) end
local function Ln(x, y) gc:lineTo(X(x, y)) end
local function C(a, b, c, d, e, f)
  local x1, y1 = X(a, b); local x2, y2 = X(c, d); local x3, y3 = X(e, f)
  gc:cubicTo(x1, y1, x2, y2, x3, y3)
end

local function poly(pts)
  gc:beginPath(); gc:moveTo(pts[1][1], pts[1][2])
  for i = 2, #pts do gc:lineTo(pts[i][1], pts[i][2]) end
  gc:closePath(); gc:fill()
end
local function circle(x, y, r) local cx, cy = X(x, y); gc:beginPath(); gc:oval(Rectangle(cx - r, cy - r, 2 * r, 2 * r)); gc:fill() end

-- ink background
gc.color = Color{r=12, g=11, b=13}
gc:beginPath(); gc:rect(Rectangle(0, 0, S, S)); gc:fill()

-- projector beam: stacked translucent cones fake a soft falloff
local ax, ay = 150, 140
local dir = math.atan(560 - ay, 520 - ax)
for _, spread in ipairs({0.46, 0.38, 0.30, 0.22, 0.14}) do
  gc.color = Color{r=255, g=176, b=60, a=13}
  poly({{ax, ay},
        {ax + 1800 * math.cos(dir - spread), ay + 1800 * math.sin(dir - spread)},
        {ax + 1800 * math.cos(dir + spread), ay + 1800 * math.sin(dir + spread)}})
end
for _, r in ipairs({150, 100, 64, 36}) do gc.color = Color{r=255, g=200, b=110, a=26}; circle(ax, ay, r) end
gc.color = Color{r=255, g=236, b=200}; circle(ax, ay, 16)

-- ticket outline with semicircle notches, centered at origin
local w, h, r, n, k = 700, 380, 46, 58, 0.5523
local function ticketPath()
  local L, R, T, B = -w / 2, w / 2, -h / 2, h / 2
  gc:beginPath()
  M(L + r, T); Ln(R - r, T)
  C(R - r + k * r, T, R, T + r - k * r, R, T + r)
  Ln(R, -n)
  C(R - k * n, -n, R - n, -k * n, R - n, 0)
  C(R - n, k * n, R - k * n, n, R, n)
  Ln(R, B - r)
  C(R, B - r + k * r, R - r + k * r, B, R - r, B)
  Ln(L + r, B)
  C(L + r - k * r, B, L, B - r + k * r, L, B - r)
  Ln(L, n)
  C(L + k * n, n, L + n, k * n, L + n, 0)
  C(L + n, -k * n, L + k * n, -n, L, -n)
  Ln(L, T + r)
  C(L, T + r - k * r, L + r - k * r, T, L + r, T)
  gc:closePath()
end

local baseX, baseY = 522, 580
rot = -math.pi / 16
local function at() ox, oy = baseX, baseY end
at()

-- soft drop shadow
for i = 1, 6 do
  ox, oy = baseX, baseY + 18 + i * 6
  gc.color = Color{r=0, g=0, b=0, a=30}; ticketPath(); gc:fill()
end
-- slab edge, then face
ox, oy = baseX, baseY + 16; gc.color = Color{r=176, g=98, b=22}; ticketPath(); gc:fill()
at()
gc.color = Color{r=255, g=176, b=60}; ticketPath(); gc:fill()

-- perforation
local px = w / 2 - 210
gc.color = Color{r=201, g=118, b=31}
for y = -h / 2 + 34, h / 2 - 30, 36 do circle(px, y, 9) end

-- play glyph with rounded corners
gc.color = Color{r=12, g=11, b=13}
gc.strokeWidth = 34
local cx = -w / 2 + 230
local tri = {{cx - 50, -74}, {cx + 78, 0}, {cx - 50, 74}}
gc:beginPath(); M(tri[1][1], tri[1][2]); Ln(tri[2][1], tri[2][2]); Ln(tri[3][1], tri[3][2]); gc:closePath()
gc:fill(); gc:stroke()

-- punch hole in the stub
circle(w / 2 - 105, 0, 44)

spr:saveAs(app.fs.joinPath(app.fs.currentPath, "Design/icon.aseprite"))
spr:saveCopyAs(app.fs.joinPath(app.fs.currentPath, "Design/icon-1024.png"))
