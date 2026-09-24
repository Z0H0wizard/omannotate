.pragma library

// Line model for OmAnnotate: fading lines drawn with SUPER+CTRL+drag.
// Pure logic with no QML, so it can be tested outside the shell. Service.qml
// owns the clock, the Hyprland events and the rendering.

var FADE = 0.5
var FRAME = 1 / 60
var MAX_POINTS = 5000
var OUTLINE_EXTRA = 2.5  // A faint dark edge keeps lines readable on light and dark content.
var OUTLINE_ALPHA = 0.35
var EVENT = "omannotate"

// Width in logical pixels, seconds shown after the last line before fading,
// percent opacity, whether lines follow the theme's accent color, and the
// #RRGGBB color used when they don't.
var DEFAULTS = { width: 4, hold: 1.5, opacity: 80, useThemeColor: true, color: "#FF3B5C" }
var LIMITS = { width: [1, 12], hold: [0.5, 10], opacity: [10, 100] }

function isColor(value) {
  return typeof value === "string" && /^#[0-9A-Fa-f]{6}$/.test(value)
}

// Settings from shell.json plus the current theme's accent. Unreadable values
// never stop drawing: they fall back to the defaults, and numbers are kept
// inside the limits. `color` is the color lines are drawn in; `customColor`
// is the stored one that theme changes never overwrite.
function style(settings, themeColor) {
  var given = settings || {}
  var result = {}
  for (var key in LIMITS) {
    var value = given[key]
    if (typeof value !== "number" || !isFinite(value)) value = DEFAULTS[key]
    result[key] = Math.min(LIMITS[key][1], Math.max(LIMITS[key][0], value))
  }
  result.useThemeColor = given.useThemeColor !== false
  result.customColor = isColor(given.color) ? given.color.toUpperCase() : DEFAULTS.color
  result.color = result.useThemeColor && isColor(themeColor) ? themeColor.toUpperCase() : result.customColor
  result.outline = result.width + OUTLINE_EXTRA
  return result
}

// What is stored in shell.json for a style.
function stored(lineStyle) {
  return {
    width: lineStyle.width,
    hold: lineStyle.hold,
    opacity: lineStyle.opacity,
    useThemeColor: lineStyle.useThemeColor,
    color: lineStyle.customColor
  }
}

// The color typed into the settings field, as "#RRGGBB", or null when it is not
// a change: invalid, or the color already shown ("RRGGBB" without # is fine).
function editedColor(text, current) {
  var value = String(text || "").trim()
  if (/^[0-9A-Fa-f]{6}$/.test(value)) value = "#" + value
  if (!isColor(value)) return null
  value = value.toUpperCase()
  return value === String(current || "").toUpperCase() ? null : value
}

// Swatches for the settings panel: the theme's accent and its named colors
// from colors.toml, without repeats, so the choices change with the theme.
var PALETTE_KEYS = ["red", "orange", "yellow", "green", "cyan", "blue", "magenta", "foreground"]

function themePalette(colorsToml, accent, limit) {
  var named = {}
  String(colorsToml || "").split("\n").forEach(function(line) {
    var match = /^\s*([a-z_]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})["']?\s*$/.exec(line)
    if (match) named[match[1]] = match[2].toUpperCase()
  })
  var result = []
  var candidates = [accent].concat(PALETTE_KEYS.map(function(key) { return named[key] }))
  for (var i = 0; i < candidates.length && result.length < (limit || 8); i++) {
    var value = isColor(candidates[i]) ? candidates[i].toUpperCase() : null
    if (value && result.indexOf(value) < 0) result.push(value)
  }
  return result
}

// "#RRGGBB" for a QML color (components 0..1).
function hex(color) {
  if (!color) return ""
  function part(value) {
    var byte = Math.max(0, Math.min(255, Math.round(value * 255)))
    return (byte < 16 ? "0" : "") + byte.toString(16).toUpperCase()
  }
  return "#" + part(color.r) + part(color.g) + part(color.b)
}

// Lines drawn close together fade together, so an arrow's parts vanish at once.
function Ink(hold) {
  this.hold = hold === undefined ? DEFAULTS.hold : hold
  this.strokes = []
  this.drawing = null
}

Ink.prototype.start = function(x, y, now) {
  if (this.drawing) this.end(now)
  for (var i = 0; i < this.strokes.length; i++) {
    var stroke = this.strokes[i]
    // Rejoin the new line's group unless the fade is already visible.
    if (stroke.fadeStart !== null && stroke.fadeStart > now) stroke.fadeStart = null
  }
  this.drawing = { points: [[x, y]], fadeStart: null }
  this.strokes.push(this.drawing)
}

Ink.prototype.extend = function(x, y) {
  var points = this.drawing ? this.drawing.points : null
  if (!points || points.length >= MAX_POINTS) return false
  var last = points[points.length - 1]
  if (Math.abs(x - last[0]) < 0.5 && Math.abs(y - last[1]) < 0.5) return false
  points.push([x, y])
  return true
}

Ink.prototype.end = function(now) {
  if (!this.drawing) return false
  this.drawing = null
  for (var i = 0; i < this.strokes.length; i++)
    if (this.strokes[i].fadeStart === null) this.strokes[i].fadeStart = now + this.hold
  return true
}

Ink.prototype.clear = function() {
  var changed = this.strokes.length > 0
  this.strokes = []
  this.drawing = null
  return changed
}

Ink.prototype.alpha = function(stroke, now) {
  if (stroke.fadeStart === null || now < stroke.fadeStart) return 1
  return Math.max(0, 1 - (now - stroke.fadeStart) / FADE)
}

Ink.prototype.fading = function(now) {
  return this.strokes.some(function(s) { return s.fadeStart !== null && s.fadeStart <= now })
}

Ink.prototype.prune = function(now) {
  var count = this.strokes.length
  this.strokes = this.strokes.filter(function(s) { return s.fadeStart === null || now < s.fadeStart + FADE })
  return this.strokes.length !== count
}

// Seconds until something visibly changes, or null when nothing will. Moving
// the cursor arrives as events, so drawing alone needs no frames.
Ink.prototype.nextFrame = function(now) {
  var starts = this.strokes.filter(function(s) { return s.fadeStart !== null })
    .map(function(s) { return s.fadeStart })
  if (!starts.length) return null
  var first = Math.min.apply(null, starts)
  return first <= now ? FRAME : first - now
}

function createInk(hold) {
  return new Ink(hold)
}

// {type: "start"|"move", x, y}, {type: "end"} or null for one Hyprland event.
function parse(name, data) {
  if (name !== "custom" || typeof data !== "string") return null
  var words = data.split(" ").filter(function(w) { return w !== "" })
  if (words[0] !== EVENT) return null
  if (words.length === 2 && words[1] === "end") return { type: "end" }
  if (words.length === 4 && (words[1] === "start" || words[1] === "move")) {
    var x = Number(words[2]), y = Number(words[3])
    if (words[2] !== "" && words[3] !== "" && isFinite(x) && isFinite(y)) return { type: words[1], x: x, y: y }
  }
  return null
}

function round(value) {
  return Math.round(value * 100) / 100
}

// Smooth the sampled cursor path with quadratic curves through midpoints,
// as SVG path data relative to (ox, oy).
function svgPath(points, ox, oy) {
  function at(point) { return round(point[0] - ox) + " " + round(point[1] - oy) }
  var path = "M " + at(points[0])
  if (points.length === 1) {
    // A click without movement draws a round dot.
    return path + " L " + round(points[0][0] - ox + 0.01) + " " + round(points[0][1] - oy)
  }
  if (points.length === 2) return path + " L " + at(points[1])
  for (var i = 1; i < points.length - 1; i++) {
    var control = points[i], following = points[i + 1]
    var end = [(control[0] + following[0]) / 2, (control[1] + following[1]) / 2]
    path += " Q " + at(control) + " " + at(end)
  }
  return path + " L " + at(points[points.length - 1])
}

// Bounds and path for one stroke, cached until it grows or the width changes.
// Layers are sized to these bounds, never to the whole screen.
function geometry(stroke, lineStyle) {
  var points = stroke.points
  var cached = stroke.geometry
  if (cached && cached.count === points.length && cached.outline === lineStyle.outline) return cached
  var xs = points.map(function(p) { return p[0] })
  var ys = points.map(function(p) { return p[1] })
  var pad = lineStyle.outline / 2 + 1
  var x = Math.min.apply(null, xs) - pad, y = Math.min.apply(null, ys) - pad
  stroke.geometry = {
    count: points.length,
    outline: lineStyle.outline,
    x: x,
    y: y,
    width: Math.max.apply(null, xs) - Math.min.apply(null, xs) + 2 * pad,
    height: Math.max.apply(null, ys) - Math.min.apply(null, ys) + 2 * pad,
    path: svgPath(points, x, y)
  }
  return stroke.geometry
}
