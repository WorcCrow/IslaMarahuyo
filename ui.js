/* ===========================================================
   Isla Marahuyo — page behaviour
   Maps scroll position onto a dive depth, feeds it to the 3D
   scene, and drives the depth HUD, reveals, nav and audio.
   =========================================================== */
(function () {
  'use strict';

  function clamp(v, a, b) { return v < a ? a : (v > b ? b : v); }
  function lerp(a, b, t) { return a + (b - a) * t; }
  function smoothstep(e0, e1, x) {
    if (e1 === e0) return 0;
    var t = clamp((x - e0) / (e1 - e0), 0, 1);
    return t * t * (3 - 2 * t);
  }

  var MAX_DEPTH = 67;

  /* -----------------------------------------------------------
     Scroll → depth
     ----------------------------------------------------------- */
  var sections = Array.prototype.slice.call(document.querySelectorAll('[data-depth]'));
  var keys = [];

  function measure() {
    keys = sections.map(function (s) {
      var r = s.getBoundingClientRect();
      return {
        c: r.top + window.pageYOffset + r.height / 2,
        d: parseFloat(s.getAttribute('data-depth')) || 0,
        n: parseFloat(s.getAttribute('data-night')) || 0
      };
    });
  }

  function sample() {
    if (!keys.length) return { d: 0, n: 0 };
    var y = window.pageYOffset + window.innerHeight / 2;
    if (y <= keys[0].c) return { d: keys[0].d, n: keys[0].n };
    for (var i = 0; i < keys.length - 1; i++) {
      if (y <= keys[i + 1].c) {
        var t = smoothstep(keys[i].c, keys[i + 1].c, y);
        return { d: lerp(keys[i].d, keys[i + 1].d, t), n: lerp(keys[i].n, keys[i + 1].n, t) };
      }
    }
    var last = keys[keys.length - 1];
    return { d: last.d, n: last.n };
  }

  measure();
  window.addEventListener('resize', measure);
  window.addEventListener('load', measure);

  /* -----------------------------------------------------------
     Depth HUD
     ----------------------------------------------------------- */
  var hud = document.getElementById('hud');
  var hudFill = document.getElementById('hud-fill');
  var hudMarker = document.getElementById('hud-marker');
  var hudNum = document.getElementById('hud-num');
  var hudZone = document.getElementById('hud-zone');
  var hudRisk = document.getElementById('hud-risk');
  var hudEarn = document.getElementById('hud-earn');
  var bar = document.querySelector('#progress span');

  // Payouts are the Palengke sell prices in ItemConfig.Loot; keep them in step with the game.
  var ZONES = [
    { to: 1, name: 'Ibabaw · Surface', risk: 'safe', label: 'Safe', earn: 'Palengke, bangka, job board' },
    { to: 15, name: 'Kabibe · Shallows', risk: 'safe', label: 'Low', earn: 'Kabibe 10 Peso · 45 s of air' },
    { to: 20.5, name: 'Bahura · Reef band', risk: 'mid', label: 'Moderate · sharks', earn: 'Bahura coral 26 Peso · lambat nets' },
    { to: 40, name: 'Yungib · The cave', risk: 'high', label: 'High · air', earn: 'Cave pearl 95 Peso · 3 Lung Corals hidden' },
    { to: 999, name: 'Kailaliman · Past the last air', risk: 'high', label: 'Extreme', earn: '200–600 Peso · hoards, kristal, Perlas Hollow' }
  ];

  function zoneFor(d) {
    for (var i = 0; i < ZONES.length; i++) if (d < ZONES[i].to) return ZONES[i];
    return ZONES[ZONES.length - 1];
  }

  var lastZone = null;
  var lastNum = null;

  function paintHud(depth) {
    var shown = Math.max(0, Math.round(depth));
    if (hudNum && shown !== lastNum) {
      hudNum.textContent = shown;
      lastNum = shown;
    }
    var p = clamp(depth / MAX_DEPTH, 0, 1) * 100;
    hudFill.style.height = p + '%';
    hudMarker.style.top = p + '%';

    var z = zoneFor(depth);
    if (z !== lastZone) {
      hudZone.textContent = z.name;
      hudRisk.textContent = z.label;
      hudRisk.setAttribute('data-risk', z.risk);
      hudEarn.textContent = z.earn;
      lastZone = z;
    }
  }

  /* -----------------------------------------------------------
     Loop: push the sampled depth into the scene, paint the HUD
     with the scene's own eased depth so the two stay in step.
     ----------------------------------------------------------- */
  var fallbackDepth = sample().d;

  function tick() {
    requestAnimationFrame(tick);

    var s = sample();
    if (window.IslaScene && window.IslaScene.ready) {
      window.IslaScene.setTarget(s.d, s.n);
    }

    var shownDepth = (window.IslaScene && window.IslaScene.getDepth)
      ? window.IslaScene.getDepth()
      : (fallbackDepth += (s.d - fallbackDepth) * 0.08);

    paintHud(shownDepth);

    var doc = document.documentElement;
    var max = doc.scrollHeight - window.innerHeight;
    bar.style.width = (max > 0 ? clamp(window.pageYOffset / max, 0, 1) * 100 : 0) + '%';

    if (hud) hud.classList.toggle('on', window.pageYOffset > window.innerHeight * 0.55);
  }
  tick();

  /* -----------------------------------------------------------
     Reveal on scroll
     ----------------------------------------------------------- */
  var reveals = document.querySelectorAll('.reveal');
  if ('IntersectionObserver' in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) {
          e.target.classList.add('in');
          io.unobserve(e.target);
        }
      });
    }, { rootMargin: '0px 0px -12% 0px', threshold: 0.08 });
    Array.prototype.forEach.call(reveals, function (el) { io.observe(el); });
  } else {
    Array.prototype.forEach.call(reveals, function (el) { el.classList.add('in'); });
  }

  /* -----------------------------------------------------------
     Mobile nav
     ----------------------------------------------------------- */
  var menuBtn = document.getElementById('menu-btn');
  var nav = document.getElementById('nav');
  if (menuBtn && nav) {
    menuBtn.addEventListener('click', function () {
      var open = nav.classList.toggle('open');
      menuBtn.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
    nav.addEventListener('click', function (e) {
      if (e.target.tagName === 'A') {
        nav.classList.remove('open');
        menuBtn.setAttribute('aria-expanded', 'false');
      }
    });
  }

  /* -----------------------------------------------------------
     Island music — off until asked for
     ----------------------------------------------------------- */
  var audio = document.getElementById('bg-audio');
  var soundBtn = document.getElementById('sound-btn');
  if (audio && soundBtn) {
    audio.volume = 0;
    var fade = null;

    function fadeTo(target, done) {
      clearInterval(fade);
      fade = setInterval(function () {
        audio.volume = clamp(audio.volume + (target > audio.volume ? 0.03 : -0.03), 0, 1);
        if (Math.abs(audio.volume - target) < 0.031) {
          audio.volume = target;
          clearInterval(fade);
          if (done) done();
        }
      }, 40);
    }

    soundBtn.addEventListener('click', function () {
      var on = soundBtn.getAttribute('aria-pressed') === 'true';
      if (on) {
        fadeTo(0, function () { audio.pause(); });
        soundBtn.setAttribute('aria-pressed', 'false');
        soundBtn.title = 'Island music';
      } else {
        var p = audio.play();
        if (p && p.catch) p.catch(function () { /* blocked by the browser */ });
        fadeTo(0.35);
        soundBtn.setAttribute('aria-pressed', 'true');
        soundBtn.title = 'Mute island music';
      }
    });
  }
})();
