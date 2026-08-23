/**
 * starfield.js — shared galaxy/starfield background.
 *
 * A standalone, dependency-free starfield that works on any page:
 * creates its own full-viewport <canvas>, paints a deep-space field of
 * twinkling stars, and (optionally) plays the same intro the main site uses —
 * stars burst outward from the center, then settle and gently drift.
 *
 * Usage:
 *   <script src="starfield.js"></script>
 *   <script>Starfield.start();</script>
 *
 * Or let it auto-start on DOMContentLoaded (default) with:
 *   <script>window.STARFIELD_AUTO = false</script>   before including, to disable.
 *
 * Options (pass to Starfield.start or set globals before include):
 *   warp        (bool)   play the center-burst intro. Default false.
 *   warpDuration(ms)     intro length. Default 1800.
 *   density     (num)    stars per px². Default ~2.06e-4 (260 @ 1400x900).
 *                        Uncapped by default: count scales with viewport
 *                        area so density (dots per px²) stays constant
 *                        across phone/tablet/desktop/ultrawide — a big
 *                        monitor shows proportionally more stars rather
 *                        than the same fixed count spread thin.
 *   maxStars    (num)    optional safety ceiling on total star count for
 *                        extreme viewports (e.g. multi-monitor spans).
 *                        Default 0 (no ceiling).
 *   hueBlueProb (num)    chance a star is tinted blue. Default 0.075.
 *   hueGoldProb (num)    chance a star is tinted gold. Default 0.075.
 *   drift       (bool)   slow post-settle upward drift. Default true.
 *   zIndex      (num)    canvas z-index. Default 0.
 */
(function (global) {
  "use strict";

  function colorFor(hue, alpha) {
    if (hue === "blue") return "rgba(180, 210, 255, " + alpha + ")";
    if (hue === "gold") return "rgba(255, 224, 178, " + alpha + ")";
    return "rgba(255, 255, 255, " + alpha + ")";
  }

  function easeOutExpo(x) { return x === 1 ? 1 : 1 - Math.pow(2, -10 * x); }

  function Starfield(canvas, opts) {
    opts = opts || {};
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    this.DPR = Math.min(global.devicePixelRatio || 1, 2);

    this.warp = opts.warp !== undefined ? opts.warp
      : (global.STARFIELD_WARP !== undefined ? global.STARFIELD_WARP : false);
    this.warpDuration = opts.warpDuration || global.STARFIELD_WARP_DURATION || 1800;
    this.density = opts.density || global.STARFIELD_DENSITY || (260 / (1400 * 900));
    this.hueBlueProb = opts.hueBlueProb !== undefined ? opts.hueBlueProb
      : (global.STARFIELD_BLUE !== undefined ? global.STARFIELD_BLUE : 0.075);
    this.hueGoldProb = opts.hueGoldProb !== undefined ? opts.hueGoldProb
      : (global.STARFIELD_GOLD !== undefined ? global.STARFIELD_GOLD : 0.075);
    this.drift = opts.drift !== undefined ? opts.drift
      : (global.STARFIELD_DRIFT !== undefined ? global.STARFIELD_DRIFT : true);
    this.maxStars = opts.maxStars !== undefined ? opts.maxStars
      : (global.STARFIELD_MAX_STARS !== undefined ? global.STARFIELD_MAX_STARS : 0);
    this.zIndex = opts.zIndex !== undefined ? opts.zIndex
      : (global.STARFIELD_Z !== undefined ? global.STARFIELD_Z : 0);
    this.bg = opts.bg || global.STARFIELD_BG || "#030209";
    this.universeMargin = opts.universeMargin || 0.6;

    this.stars = [];
    this.running = false;
    this.width = 0; this.height = 0;
    this.startTime = 0;
    this._boundDraw = this._draw.bind(this);

    this._style();
    this.resize();
    this._makeStars();
    global.addEventListener("resize", this.resize.bind(this));
  }

  Starfield.prototype._style = function () {
    var c = this.canvas;
    c.style.position = "fixed";
    c.style.top = "0";
    c.style.left = "0";
    c.style.width = "100%";
    c.style.height = "100%";
    c.style.pointerEvents = "none";
    c.style.zIndex = String(this.zIndex);
    c.setAttribute("data-starfield", "");
  };

  Starfield.prototype.resize = function () {
    this.width = global.innerWidth;
    this.height = global.innerHeight;
    this.canvas.width = this.width * this.DPR;
    this.canvas.height = this.height * this.DPR;
    this.canvas.style.width = this.width + "px";
    this.canvas.style.height = this.height + "px";
    this.ctx.setTransform(this.DPR, 0, 0, this.DPR, 0, 0);
  };

  Starfield.prototype._makeStars = function () {
    var w = this.width * (1 + this.universeMargin * 2);
    var h = this.height * (1 + this.universeMargin * 2);
    // No hard cap: count scales purely off density × area, so a phone
    // screen and an ultrawide monitor look equally "starry" (same dots
    // per px²) instead of big screens getting diluted by an arbitrary
    // ceiling. maxStars is an optional safety valve for absurd viewport
    // sizes (multi-monitor spans), left effectively unbounded by default.
    var count = Math.round(w * h * this.density);
    if (this.maxStars) count = Math.min(this.maxStars, count);
    this.stars = [];
    for (var i = 0; i < count; i++) {
      var ux = (Math.random() - 0.5) * w;
      var uy = (Math.random() - 0.5) * h;
      var angle = Math.atan2(uy, ux);
      var dist = Math.sqrt(ux * ux + uy * uy);
      var sizeRoll = Math.random();
      var r = sizeRoll < 0.75 ? 0.4 + Math.random() * 0.5
            : sizeRoll < 0.95 ? 0.9 + Math.random() * 0.5
            : 1.4 + Math.random() * 0.6;
      var hue = "white";
      var roll = Math.random();
      if (roll < this.hueBlueProb) hue = "blue";
      else if (roll < this.hueBlueProb + this.hueGoldProb) hue = "gold";
      this.stars.push({
        angle: angle, dist: dist, universeX: ux, universeY: uy, r: r,
        alpha: 0.4 + Math.random() * 0.6,
        speed: 0.01 + Math.random() * 0.06,
        delay: Math.random() * 250,
        len: 20 + Math.random() * 60,
        lineWidth: 0.6 + Math.random() * 1.4,
        hue: hue,
        twinkleSpeed: 0.002 + Math.random() * 0.006,
        twinkleOffset: Math.random() * Math.PI * 2,
      });
    }
  };

  Starfield.prototype._drawWarpFlash = function (elapsed) {
    var p = Math.min(1, elapsed / 220);
    if (p < 1) {
      this.ctx.fillStyle = "rgba(200, 190, 255, " + ((1 - p) * 0.35) + ")";
      this.ctx.fillRect(0, 0, this.width, this.height);
    }
  };

  Starfield.prototype._draw = function (now) {
    if (!this.running) return;
    var elapsed = now - this.startTime;
    var ctx = this.ctx;
    var cx = this.width / 2, cy = this.height / 2;
    var universeH = this.height * (1 + this.universeMargin * 2);

    ctx.fillStyle = this.bg;
    ctx.fillRect(0, 0, this.width, this.height);

    for (var i = 0; i < this.stars.length; i++) {
      var s = this.stars[i];
      var local = Math.max(0, elapsed - s.delay);
      var progress = this.warp ? Math.min(1, local / (this.warpDuration - s.delay)) : 1;

      if (progress < 1) {
        // In-flight streak traveling from center toward its resting spot.
        var eased = easeOutExpo(progress);
        var x = cx + Math.cos(s.angle) * s.dist * eased;
        var y = cy + Math.sin(s.angle) * s.dist * eased;
        var sf = Math.max(0, 1 - progress);
        var len = s.len * sf + 1;
        var tx = x - Math.cos(s.angle) * len;
        var ty = y - Math.sin(s.angle) * len;
        var grad = ctx.createLinearGradient(tx, ty, x, y);
        grad.addColorStop(0, colorFor(s.hue, 0));
        grad.addColorStop(1, colorFor(s.hue, 0.85));
        ctx.strokeStyle = grad;
        ctx.lineWidth = s.lineWidth;
        ctx.beginPath();
        ctx.moveTo(tx, ty);
        ctx.lineTo(x, y);
        ctx.stroke();
      } else {
        var sx = cx + s.universeX;
        var sy = cy + s.universeY;
        if (!(sx < -4 || sx > this.width + 4 || sy < -4 || sy > this.height + 4)) {
          var tw = Math.sin(now * s.twinkleSpeed + s.twinkleOffset);
          var a = Math.max(0.15, Math.min(1, s.alpha + tw * 0.25));
          ctx.beginPath();
          ctx.arc(sx, sy, s.r, 0, Math.PI * 2);
          ctx.fillStyle = colorFor(s.hue, a);
          ctx.fill();
        }
        if (this.drift) {
          s.universeY -= s.speed;
          if (s.universeY < -universeH / 2 - 2) {
            s.universeY = universeH / 2 + 2;
            s.universeX = (Math.random() - 0.5) * this.width * (1 + this.universeMargin * 2);
          }
        }
      }
    }

    if (this.warp && elapsed < this.warpDuration) this._drawWarpFlash(elapsed);
    requestAnimationFrame(this._boundDraw);
  };

  Starfield.prototype.start = function () {
    if (this.running) return this;
    this.running = true;
    this.startTime = performance.now();
    requestAnimationFrame(this._boundDraw);
    return this;
  };

  Starfield.prototype.stop = function () { this.running = false; return this; };
  Starfield.prototype.destroy = function () {
    this.running = false;
    if (this.canvas.parentNode) this.canvas.parentNode.removeChild(this.canvas);
    return this;
  };

  // Public API
  var api = {
    Starfield: Starfield,
    create: function (opts) {
      var c = document.createElement("canvas");
      (document.body || document.documentElement).prepend(c);
      return new Starfield(c, opts);
    },
    start: function (canvasOrOpts, maybeOpts) {
      var canvas, opts;
      if (canvasOrOpts && canvasOrOpts.getContext) { canvas = canvasOrOpts; opts = maybeOpts; }
      else { opts = canvasOrOpts; }
      if (!canvas) { return api.create(opts).start(); }
      var sf = new Starfield(canvas, opts);
      return sf.start();
    },
  };

  global.Starfield = api;

  // Auto-start on DOMContentLoaded unless disabled.
  var auto = global.STARFIELD_AUTO !== undefined ? global.STARFIELD_AUTO : true;
  if (auto && !global.__STARFIELD_MANUAL) {
    var boot = function () { if (!global.__starfieldInstance) { global.__starfieldInstance = api.start(); } };
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
    else boot();
  }
})(typeof window !== "undefined" ? window : this);
