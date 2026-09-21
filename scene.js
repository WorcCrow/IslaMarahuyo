/* ===========================================================
   Isla Marahuyo — 3D dive scene (three.js r149, UMD build)

   One fixed WebGL canvas behind the page. Scrolling moves the
   camera down a water column: sunset surface → reef → limestone
   shaft → the 67 m abyss → and back up to the market.

   Everything is procedural (no texture files), so the page works
   straight off the filesystem with no server.
   =========================================================== */
(function () {
  'use strict';

  var root = document.documentElement;
  var canvas = document.getElementById('scene');

  if (!window.THREE || !canvas) { root.classList.add('no-3d'); return; }

  var renderer;
  try {
    renderer = new THREE.WebGLRenderer({
      canvas: canvas,
      antialias: window.devicePixelRatio < 1.6,
      powerPreference: 'high-performance',
      stencil: false
    });
  } catch (err) {
    root.classList.add('no-3d');
    return;
  }

  // Proper sRGB pipeline: hex colours are treated as sRGB going in,
  // lit in linear space, encoded back on the way out. Without this the
  // whole scene comes out milky.
  if (THREE.ColorManagement) THREE.ColorManagement.legacyMode = false;

  var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var lowPower = window.matchMedia('(max-width: 760px)').matches;

  var maxDPR = lowPower ? 1.5 : 1.75;
  var pixelRatio = Math.min(window.devicePixelRatio || 1, maxDPR);
  renderer.setPixelRatio(pixelRatio);
  renderer.setSize(window.innerWidth, window.innerHeight, false);
  renderer.outputEncoding = THREE.sRGBEncoding;

  /* -----------------------------------------------------------
     Small helpers
     ----------------------------------------------------------- */
  var TAU = Math.PI * 2;
  function clamp(v, a, b) { return v < a ? a : (v > b ? b : v); }
  function lerp(a, b, t) { return a + (b - a) * t; }
  function smoothstep(e0, e1, x) { var t = clamp((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t); }
  function rand(a, b) { return a + Math.random() * (b - a); }

  function hash2(x, y) {
    var s = Math.sin(x * 127.1 + y * 311.7) * 43758.5453123;
    return s - Math.floor(s);
  }
  function vnoise(x, y) {
    var xi = Math.floor(x), yi = Math.floor(y);
    var xf = x - xi, yf = y - yi;
    var u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
    var a = hash2(xi, yi), b = hash2(xi + 1, yi), c = hash2(xi, yi + 1), d = hash2(xi + 1, yi + 1);
    return a * (1 - u) * (1 - v) + b * u * (1 - v) + c * (1 - u) * v + d * u * v;
  }
  function fbm(x, y, oct) {
    var f = 0, amp = 0.5, fr = 1;
    for (var i = 0; i < (oct || 4); i++) { f += amp * vnoise(x * fr, y * fr); fr *= 2; amp *= 0.5; }
    return f;
  }

  function softSprite() {
    var c = document.createElement('canvas');
    c.width = c.height = 64;
    var ctx = c.getContext('2d');
    var g = ctx.createRadialGradient(32, 32, 0, 32, 32, 32);
    g.addColorStop(0, 'rgba(255,255,255,1)');
    g.addColorStop(0.3, 'rgba(255,255,255,0.55)');
    g.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, 64, 64);
    var t = new THREE.CanvasTexture(c);
    t.needsUpdate = true;
    return t;
  }
  var SPRITE_TEX = softSprite();

  function ringSprite() {
    var c = document.createElement('canvas');
    c.width = c.height = 64;
    var ctx = c.getContext('2d');
    var g = ctx.createRadialGradient(32, 32, 0, 32, 32, 32);
    g.addColorStop(0, 'rgba(255,255,255,0.12)');
    g.addColorStop(0.62, 'rgba(255,255,255,0.10)');
    g.addColorStop(0.80, 'rgba(255,255,255,0.85)');
    g.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, 64, 64);
    var t = new THREE.CanvasTexture(c);
    t.needsUpdate = true;
    return t;
  }
  var BUBBLE_TEX = ringSprite();

  /* -----------------------------------------------------------
     Scene, camera, atmosphere
     ----------------------------------------------------------- */
  var COLUMN_Z = 20;                 // the dive shaft sits here
  var SUN_DIR = new THREE.Vector3(-0.46, 0.115, -1).normalize();

  var scene = new THREE.Scene();
  scene.fog = new THREE.FogExp2(0xf7b878, 0.0026);

  var camera = new THREE.PerspectiveCamera(52, window.innerWidth / window.innerHeight, 0.1, 1600);
  camera.position.set(0, 16, COLUMN_Z);

  var hemi = new THREE.HemisphereLight(0xffd7a8, 0x1d5f6b, 0.95);
  scene.add(hemi);

  var sunLight = new THREE.DirectionalLight(0xffd0a0, 1.35);
  sunLight.position.copy(SUN_DIR).multiplyScalar(220);
  scene.add(sunLight);

  var diveLight = new THREE.PointLight(0x9fe8ff, 0, 80, 1.6);
  scene.add(diveLight);

  /* ---------- sky dome ---------- */
  var skyUniforms = {
    uTop: { value: new THREE.Color(0x2f7fb8) },
    uMid: { value: new THREE.Color(0xffb06a) },
    uBot: { value: new THREE.Color(0xffd9a2) },
    uSunCol: { value: new THREE.Color(0xffd0a0) },
    uSunDir: { value: SUN_DIR.clone() },
    uSun: { value: 1 }
  };
  var sky = new THREE.Mesh(
    new THREE.SphereGeometry(760, 32, 20),
    new THREE.ShaderMaterial({
      uniforms: skyUniforms,
      side: THREE.BackSide,
      depthWrite: false,
      fog: false,
      vertexShader: [
        'varying vec3 vDir;',
        'void main(){',
        '  vDir = position;',
        '  gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0);',
        '}'
      ].join('\n'),
      fragmentShader: [
        'uniform vec3 uTop; uniform vec3 uMid; uniform vec3 uBot;',
        'uniform vec3 uSunCol; uniform vec3 uSunDir; uniform float uSun;',
        'varying vec3 vDir;',
        'void main(){',
        '  vec3 d = normalize(vDir);',
        // The camera only ever sees a narrow band of elevation, so ramp on the
        // raw elevation rather than a remapped 0..1 height.
        '  float el = d.y;',
        '  vec3 col = mix(uBot, uMid, smoothstep(-0.04, 0.07, el));',
        '  col = mix(col, uTop, smoothstep(0.03, 0.26, el));',
        '  float sd = max(dot(d, normalize(uSunDir)), 0.0);',
        '  col += uSunCol * pow(sd, 12.0) * 0.45 * uSun;',
        '  col += uSunCol * pow(sd, 260.0) * 2.4 * uSun;',
        '  gl_FragColor = vec4(col, 1.0);',
        '}'
      ].join('\n')
    })
  );
  sky.renderOrder = -10;
  scene.add(sky);

  /* ---------- sun ---------- */
  var sunCore = new THREE.Sprite(new THREE.SpriteMaterial({
    map: SPRITE_TEX, color: 0xfff1cf, transparent: true, depthWrite: false,
    blending: THREE.AdditiveBlending, fog: false
  }));
  sunCore.scale.setScalar(120);
  sunCore.position.copy(SUN_DIR).multiplyScalar(600);
  scene.add(sunCore);

  var sunHalo = new THREE.Sprite(new THREE.SpriteMaterial({
    map: SPRITE_TEX, color: 0xffa860, transparent: true, opacity: 0.75, depthWrite: false,
    blending: THREE.AdditiveBlending, fog: false
  }));
  sunHalo.scale.setScalar(420);
  sunHalo.position.copy(sunCore.position);
  scene.add(sunHalo);

  /* -----------------------------------------------------------
     Ocean surface — Gerstner waves, shaded differently from
     above and from underneath (Snell's window).
     ----------------------------------------------------------- */
  // Wavelengths stay well above the mesh's sampling rate — shorter waves than
  // this alias into grey mush. Fine detail is added per-pixel instead.
  var WAVES = [
    { dir: [1.0, 0.35], steep: 0.095, len: 68 },
    { dir: [-0.6, 0.9], steep: 0.075, len: 37 },
    { dir: [0.3, -1.0], steep: 0.055, len: 21 }
  ];

  var waterUniforms = THREE.UniformsUtils.merge([
    THREE.UniformsLib.fog,
    {
      uTime: { value: 0 },
      uDeep: { value: new THREE.Color(0x0b4b6b) },
      uShallow: { value: new THREE.Color(0x2fb6c4) },
      uFoam: { value: new THREE.Color(0xf4ffff) },
      uSunCol: { value: new THREE.Color(0xffd3a0) },
      uUnder: { value: new THREE.Color(0x0a4a63) },
      uSky: { value: new THREE.Color(0xffb07a) },
      uSunDir: { value: SUN_DIR.clone() },
      uAmp: { value: 1 }
    }
  ]);

  var waterVert = [
    'uniform float uTime; uniform float uAmp;',
    'varying vec3 vWorld; varying vec3 vNrm; varying float vCrest;',
    '#include <fog_pars_vertex>',
    'vec3 gerstner(vec2 dir, float steep, float len, vec2 p, float t, inout vec3 tan, inout vec3 bin){',
    '  float k = 6.2831853 / len;',
    '  float c = sqrt(9.8 / k);',
    '  vec2 d = normalize(dir);',
    '  float f = k * (dot(d, p) - c * t);',
    '  float a = steep / k;',
    '  float sf = sin(f); float cf = cos(f);',
    '  tan += vec3(-d.x*d.x*(steep*sf), d.x*(steep*cf), -d.x*d.y*(steep*sf));',
    '  bin += vec3(-d.x*d.y*(steep*sf), d.y*(steep*cf), -d.y*d.y*(steep*sf));',
    '  return vec3(d.x*(a*cf), a*sf, d.y*(a*cf));',
    '}',
    'void main(){',
    '  vec3 p = position;',
    '  vec2 gp = p.xz;',
    '  float damp = mix(0.28, 1.0, 1.0 - smoothstep(140.0, 520.0, length(gp))) * uAmp;',
    '  vec3 tan = vec3(1.0,0.0,0.0); vec3 bin = vec3(0.0,0.0,1.0);',
    '  vec3 disp = vec3(0.0);',
    'WAVE_CALLS',
    '  disp *= damp;',
    '  vec3 pos = p + disp;',
    '  vNrm = normalize(cross(bin, tan));',
    '  vCrest = smoothstep(0.95, 1.45, disp.y);',
    '  vec4 wp = modelMatrix * vec4(pos, 1.0);',
    '  vWorld = wp.xyz;',
    '  vec4 mvPosition = viewMatrix * wp;',
    '  gl_Position = projectionMatrix * mvPosition;',
    '  #include <fog_vertex>',
    '}'
  ].join('\n');

  var waveCalls = WAVES.map(function (w) {
    return '  disp += gerstner(vec2(' + w.dir[0].toFixed(3) + ',' + w.dir[1].toFixed(3) + '), ' +
      w.steep.toFixed(4) + ', ' + w.len.toFixed(2) + ', gp, uTime, tan, bin);';
  }).join('\n');

  var waterFrag = [
    'uniform vec3 uDeep; uniform vec3 uShallow; uniform vec3 uFoam;',
    'uniform vec3 uSunCol; uniform vec3 uUnder; uniform vec3 uSky; uniform vec3 uSunDir;',
    'uniform float uTime;',
    'varying vec3 vWorld; varying vec3 vNrm; varying float vCrest;',
    '#include <fog_pars_fragment>',
    'void main(){',
    '  vec3 V = normalize(cameraPosition - vWorld);',
    '  vec3 N = normalize(vNrm);',
    // per-pixel ripple detail: sparkle without extra triangles
    '  vec2 w = vWorld.xz;',
    '  float ripple = 1.0 - smoothstep(60.0, 300.0, length(vWorld - cameraPosition));',
    '  float d1 = sin(w.x * 0.62 + uTime * 1.9) * cos(w.y * 0.51 - uTime * 1.4);',
    '  float d2 = sin((w.x + w.y * 1.3) * 0.34 - uTime * 1.1);',
    '  N = normalize(N + vec3(d1, 0.0, d2) * 0.085 * ripple);',
    '  vec3 S = normalize(uSunDir);',
    '  vec3 col;',
    '  if (gl_FrontFacing) {',
    // body colour + a fresnel reflection of the sky, which is what makes
    // water read as water at sunset
    '    float fres = pow(1.0 - clamp(dot(N, V), 0.0, 1.0), 3.5);',
    '    vec3 body = mix(uDeep, uShallow, 0.45);',
    '    col = mix(body, uSky, clamp(fres, 0.0, 1.0) * 0.72);',
    '    vec3 H = normalize(S + V);',
    '    col += uSunCol * pow(max(dot(N, H), 0.0), 120.0) * 3.0;',
    '    col += uSunCol * pow(max(dot(reflect(-V, N), S), 0.0), 9.0) * 0.35;',
    '    col = mix(col, uFoam, clamp(vCrest, 0.0, 1.0) * 0.5);',
    '  } else {',
    '    vec3 Nd = -N;',
    '    float window = smoothstep(0.30, 0.96, clamp(dot(Nd, V), 0.0, 1.0));',
    '    col = mix(uUnder, uShallow * 1.35, window);',
    '    col += uSunCol * pow(window, 3.0) * 0.55;',
    '    col = mix(col, uFoam * 0.75, clamp(vCrest, 0.0, 1.0) * 0.30);',
    '  }',
    '  gl_FragColor = vec4(col, 1.0);',
    '  #include <fog_fragment>',
    '}'
  ].join('\n');

  var waterGeo = new THREE.PlaneGeometry(1300, 1300, lowPower ? 128 : 240, lowPower ? 128 : 240);
  waterGeo.rotateX(-Math.PI / 2);
  var water = new THREE.Mesh(waterGeo, new THREE.ShaderMaterial({
    uniforms: waterUniforms,
    vertexShader: waterVert.replace('WAVE_CALLS', waveCalls),
    fragmentShader: waterFrag,
    side: THREE.DoubleSide,
    fog: true
  }));
  scene.add(water);

  // CPU copy of the wave sum, so boats float on the same water.
  function waveAt(x, z, t) {
    var y = 0;
    for (var i = 0; i < WAVES.length; i++) {
      var w = WAVES[i];
      var k = TAU / w.len;
      var c = Math.sqrt(9.8 / k);
      var len = Math.hypot(w.dir[0], w.dir[1]);
      var dx = w.dir[0] / len, dz = w.dir[1] / len;
      var f = k * (dx * x + dz * z - c * t);
      y += (w.steep / k) * Math.sin(f);
    }
    return y;
  }

  /* -----------------------------------------------------------
     Shared materials / geometry
     ----------------------------------------------------------- */
  function lam(color, opts) {
    var o = opts || {};
    o.color = color;
    o.flatShading = o.flatShading !== false;
    return new THREE.MeshLambertMaterial(o);
  }

  var MAT = {
    sand: lam(0xe8cf9a),
    rock: lam(0x5b6d72),
    darkRock: lam(0x22343d),
    bamboo: lam(0xd8b073),
    wood: lam(0x8a5a2b),
    leaf: lam(0x2f7a33),
    trunk: lam(0x7a5230),
    hull: lam(0x9b6b3a),
    cloud: lam(0xffe6cf, { emissive: 0x3a2a20 }),
    shark: lam(0x10222c)
  };

  var BOX = new THREE.BoxGeometry(1, 1, 1);
  var ROOF = new THREE.ConeGeometry(1, 1, 4).rotateY(Math.PI / 4);
  var POLE = new THREE.CylinderGeometry(1, 1, 1, 6);

  /* -----------------------------------------------------------
     The island above water
     ----------------------------------------------------------- */
  function buildIsland(R, H, seed, palette) {
    var geo = new THREE.ConeGeometry(R, H, 30, 14);
    var pos = geo.attributes.position;
    var colors = [];
    var cSand = new THREE.Color(palette.sand);
    var cGrass = new THREE.Color(palette.grass);
    var cRock = new THREE.Color(palette.rock);
    var cPeak = new THREE.Color(palette.peak);
    var tmp = new THREE.Color();

    for (var i = 0; i < pos.count; i++) {
      var x = pos.getX(i), y = pos.getY(i), z = pos.getZ(i);
      var h = (y + H / 2) / H;
      var r = Math.hypot(x, z);
      if (r > 0.02) {
        var ang = Math.atan2(z, x);
        // low-frequency lobes carve the coastline, a higher band adds ridges
        var n = fbm(Math.cos(ang) * 2.4 + seed, Math.sin(ang) * 2.4 + seed, 4);
        var ridge = fbm(Math.cos(ang) * 7.5 + seed * 2, Math.sin(ang) * 7.5 + h * 3.5, 3);
        var bulge = 1 + (n - 0.5) * 0.66 * (1.2 - h * 0.55) + (ridge - 0.5) * 0.22 * (1 - h);
        // lean the summit off-axis so it never reads as a cone
        var lean = (1 - h) * 0;
        pos.setX(i, Math.cos(ang) * r * bulge + h * h * 9 + lean);
        pos.setZ(i, Math.sin(ang) * r * bulge - h * h * 6);
        pos.setY(i, y + (n - 0.5) * H * 0.2 * (1 - h * 0.3) + (ridge - 0.5) * H * 0.09);
      }
      if (h < 0.07) tmp.copy(cSand);
      else if (h < 0.60) tmp.copy(cGrass).lerp(cRock, smoothstep(0.34, 0.60, h) * 0.55);
      else tmp.copy(cRock).lerp(cPeak, smoothstep(0.62, 0.98, h));
      colors.push(tmp.r, tmp.g, tmp.b);
    }
    geo.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3));
    geo.translate(0, H / 2 - 3.5, 0);
    geo.computeVertexNormals();
    return new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ vertexColors: true, flatShading: true }));
  }

  function buildPalm() {
    var g = new THREE.Group();
    var trunk = new THREE.Mesh(POLE, MAT.trunk);
    var hgt = rand(5.5, 8.5);
    trunk.scale.set(0.3, hgt, 0.3);
    trunk.position.y = hgt / 2;
    trunk.rotation.z = rand(-0.22, 0.22);
    g.add(trunk);
    var frondGeo = new THREE.ConeGeometry(0.85, 4.4, 4);
    frondGeo.translate(0, 2.2, 0);
    for (var i = 0; i < 6; i++) {
      var f = new THREE.Mesh(frondGeo, MAT.leaf);
      f.position.y = hgt;
      f.rotation.y = (i / 6) * TAU + rand(-0.2, 0.2);
      f.rotation.z = rand(1.0, 1.35);
      f.scale.set(1, 1, 0.3);
      g.add(f);
    }
    return g;
  }

  var HUT_COLORS = [0xd9563f, 0x3f8fb0, 0xe0a83c, 0x4f9e5a, 0xb6564f, 0x6f7fc0];

  function buildHut(stilts) {
    var g = new THREE.Group();
    var w = rand(2.2, 3.2);
    var base = stilts ? 2.2 : 0.4;

    var walls = new THREE.Mesh(BOX, MAT.bamboo);
    walls.scale.set(w, 2.0, w * 0.86);
    walls.position.y = base + 1.0;
    g.add(walls);

    var roof = new THREE.Mesh(ROOF, lam(HUT_COLORS[(Math.random() * HUT_COLORS.length) | 0]));
    roof.scale.set(w * 0.98, 1.7, w * 0.98);
    roof.position.y = base + 2.85;
    g.add(roof);

    if (stilts) {
      for (var i = 0; i < 4; i++) {
        var p = new THREE.Mesh(POLE, MAT.wood);
        p.scale.set(0.14, base + 1.2, 0.14);
        p.position.set(
          (i % 2 ? 1 : -1) * w * 0.38,
          (base + 1.2) / 2 - 0.8,
          (i < 2 ? 1 : -1) * w * 0.32
        );
        g.add(p);
      }
    }
    return g;
  }

  function buildBangka() {
    var g = new THREE.Group();
    var hull = new THREE.Mesh(new THREE.ConeGeometry(0.85, 6.4, 4).rotateZ(-Math.PI / 2), MAT.hull);
    hull.scale.set(1, 0.55, 1);
    hull.position.y = 0.25;
    g.add(hull);

    var canopy = new THREE.Mesh(BOX, lam(HUT_COLORS[(Math.random() * HUT_COLORS.length) | 0]));
    canopy.scale.set(1.7, 0.2, 1.2);
    canopy.position.set(-0.3, 1.25, 0);
    g.add(canopy);
    for (var s = -1; s <= 1; s += 2) {
      var post = new THREE.Mesh(POLE, MAT.wood);
      post.scale.set(0.08, 1.1, 0.08);
      post.position.set(-0.3, 0.75, s * 0.45);
      g.add(post);

      var float = new THREE.Mesh(new THREE.CylinderGeometry(0.16, 0.16, 4.6, 5).rotateZ(Math.PI / 2), MAT.bamboo);
      float.position.set(0, 0.25, s * 2.5);
      g.add(float);

      for (var a = -1; a <= 1; a += 2) {
        var arm = new THREE.Mesh(POLE, MAT.bamboo);
        arm.scale.set(0.09, 2.6, 0.09);
        arm.rotation.x = s * Math.PI / 2;
        arm.position.set(a * 1.3, 0.75, s * 1.25);
        g.add(arm);
      }
    }
    return g;
  }

  var surfaceGroup = new THREE.Group();
  scene.add(surfaceGroup);

  // Main island, off to the right of the sunset.
  var island = buildIsland(74, 58, 3.1, { sand: 0xe9cf9a, grass: 0x38702a, rock: 0x4d5136, peak: 0x6e6352 });
  island.position.set(98, 0, -168);
  island.rotation.y = 0.7;
  surfaceGroup.add(island);

  // A lower shoulder ridge so the skyline is not a single cone.
  var shoulder = buildIsland(46, 30, 12.4, { sand: 0xe9cf9a, grass: 0x3d7b2f, rock: 0x4d5136, peak: 0x5f5947 });
  shoulder.position.set(36, 0, -140);
  shoulder.rotation.y = -1.2;
  surfaceGroup.add(shoulder);

  var beach = new THREE.Mesh(new THREE.CylinderGeometry(80, 94, 4, 44), MAT.sand);
  beach.position.set(98, -2.4, -168);
  surfaceGroup.add(beach);

  var beachB = new THREE.Mesh(new THREE.CylinderGeometry(50, 60, 3.2, 32), MAT.sand);
  beachB.position.set(36, -2.2, -140);
  surfaceGroup.add(beachB);

  // Companion island — Isla Ningning, far to the left.
  var island2 = buildIsland(38, 24, 8.7, { sand: 0xf0dcae, grass: 0x53964a, rock: 0x6d6b55, peak: 0x8d8778 });
  island2.position.set(-210, 0, -330);
  surfaceGroup.add(island2);
  var beach2 = new THREE.Mesh(new THREE.CylinderGeometry(43, 50, 3, 28), MAT.sand);
  beach2.position.set(-210, -1.3, -330);
  surfaceGroup.add(beach2);

  // Palms along the near shore.
  for (var pi = 0; pi < (lowPower ? 8 : 14); pi++) {
    var pa = rand(Math.PI * 0.55, Math.PI * 1.35);
    var pr = rand(60, 86);
    var palm = buildPalm();
    palm.position.set(98 + Math.cos(pa) * pr, rand(0.4, 3.2), -168 + Math.sin(pa) * pr);
    palm.scale.setScalar(rand(0.9, 1.5));
    surfaceGroup.add(palm);
  }

  // Village: huts on the beach and out over the water on stilts.
  var floaters = [];   // things that bob on the waves
  for (var hi = 0; hi < (lowPower ? 9 : 16); hi++) {
    var onWater = hi > 5;
    var ha = rand(Math.PI * 0.62, Math.PI * 1.3);
    var hr = onWater ? rand(88, 112) : rand(56, 80);
    var hut = buildHut(onWater);
    hut.position.set(98 + Math.cos(ha) * hr, onWater ? -0.6 : rand(1.5, 5.5), -168 + Math.sin(ha) * hr);
    hut.rotation.y = rand(0, TAU);
    hut.scale.setScalar(rand(0.85, 1.25));
    surfaceGroup.add(hut);
  }

  for (var bi = 0; bi < (lowPower ? 4 : 7); bi++) {
    var boat = buildBangka();
    boat.position.set(rand(-40, 150), 0, rand(-210, -70));
    boat.rotation.y = rand(0, TAU);
    boat.scale.setScalar(rand(0.9, 1.6));
    surfaceGroup.add(boat);
    floaters.push(boat);
  }

  // Sunset clouds.
  if (!lowPower) {
    var cloudGeo = new THREE.IcosahedronGeometry(1, 1);
    for (var ci = 0; ci < 7; ci++) {
      var cloud = new THREE.Group();
      for (var cj = 0; cj < 3; cj++) {
        var puff = new THREE.Mesh(cloudGeo, MAT.cloud);
        puff.position.set(cj * rand(9, 15) - 12, rand(-2, 2), rand(-4, 4));
        puff.scale.set(rand(9, 16), rand(4, 6.5), rand(7, 11));
        cloud.add(puff);
      }
      cloud.position.set(rand(-360, 360), rand(52, 105), rand(-520, -150));
      surfaceGroup.add(cloud);
    }
  }

  /* -----------------------------------------------------------
     The dive column: shelves, cave shaft, abyss, seabed
     ----------------------------------------------------------- */
  var dive = new THREE.Group();
  dive.position.set(0, 0, COLUMN_Z);
  scene.add(dive);

  function buildShelf(inner, outer, y, rough, colTop, colEdge) {
    var geo = new THREE.RingGeometry(inner, outer, 56, 7);
    geo.rotateX(-Math.PI / 2);
    var pos = geo.attributes.position;
    var colors = [];
    var cA = new THREE.Color(colTop), cB = new THREE.Color(colEdge), tmp = new THREE.Color();
    for (var i = 0; i < pos.count; i++) {
      var x = pos.getX(i), z = pos.getZ(i);
      var r = Math.hypot(x, z);
      var n = fbm(x * 0.045 + 11, z * 0.045 - 4, 4);
      pos.setY(i, (n - 0.5) * rough - smoothstep(inner, outer, r) * rough * 0.9);
      tmp.copy(cA).lerp(cB, clamp(n * 1.3 - 0.1, 0, 1));
      colors.push(tmp.r, tmp.g, tmp.b);
    }
    geo.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3));
    geo.computeVertexNormals();
    var m = new THREE.Mesh(geo, new THREE.MeshLambertMaterial({
      vertexColors: true, flatShading: true, side: THREE.DoubleSide
    }));
    m.position.y = y;
    dive.add(m);
    return m;
  }

  var shelfA = buildShelf(22, 96, -15, 5.5, 0xd8c68e, 0x6ba98f);   // Kabibe sand
  var shelfB = buildShelf(28, 132, -25, 7.5, 0x8fae86, 0x2f7d86);  // Bahura reef

  function buildWall(rTop, rBot, height, yCenter, segY, color, rough) {
    var geo = new THREE.CylinderGeometry(rTop, rBot, height, 30, segY, true);
    var pos = geo.attributes.position;
    for (var i = 0; i < pos.count; i++) {
      var x = pos.getX(i), y = pos.getY(i), z = pos.getZ(i);
      var ang = Math.atan2(z, x);
      var r = Math.hypot(x, z);
      var n = fbm(Math.cos(ang) * 3.2 + 20, Math.sin(ang) * 3.2 + y * 0.09, 4);
      var nr = r * (1 + (n - 0.5) * rough);
      pos.setX(i, Math.cos(ang) * nr);
      pos.setZ(i, Math.sin(ang) * nr);
    }
    geo.computeVertexNormals();
    var m = new THREE.Mesh(geo, lam(color, { side: THREE.BackSide }));
    m.position.y = yCenter;
    dive.add(m);
    return m;
  }

  buildWall(32, 27, 27, -40.5, 6, 0x3e5b5e, 0.26);   // Yungib limestone shaft
  buildWall(27, 88, 22, -65, 4, 0x1b2f3a, 0.20);     // opening into Kailaliman

  // Seabed
  var floorGeo = new THREE.CircleGeometry(175, 64, 0, TAU);
  floorGeo.rotateX(-Math.PI / 2);
  (function () {
    var pos = floorGeo.attributes.position;
    for (var i = 0; i < pos.count; i++) {
      var x = pos.getX(i), z = pos.getZ(i);
      pos.setY(i, (fbm(x * 0.035 + 3, z * 0.035 + 9, 4) - 0.5) * 9);
    }
    floorGeo.computeVertexNormals();
  })();
  var seabed = new THREE.Mesh(floorGeo, lam(0x22333d));
  seabed.position.y = -78;
  dive.add(seabed);

  // Scattered boulders down the shaft for a sense of scale.
  var rockGeo = new THREE.IcosahedronGeometry(1, 0);
  for (var ri = 0; ri < (lowPower ? 14 : 26); ri++) {
    var rock = new THREE.Mesh(rockGeo, MAT.darkRock);
    var ra = rand(0, TAU);
    var rr = rand(24, 70);
    rock.position.set(Math.cos(ra) * rr, rand(-76, -18), Math.sin(ra) * rr);
    rock.scale.set(rand(2, 8), rand(2, 7), rand(2, 8));
    rock.rotation.set(rand(0, TAU), rand(0, TAU), rand(0, TAU));
    dive.add(rock);
  }

  /* -----------------------------------------------------------
     Coral reef (instanced)
     ----------------------------------------------------------- */
  var CORAL_PROTOS = [
    new THREE.IcosahedronGeometry(1, 1),
    new THREE.ConeGeometry(0.55, 2.6, 5),
    new THREE.CylinderGeometry(0.34, 0.5, 2.2, 6),
    new THREE.TorusGeometry(1.0, 0.18, 4, 9).rotateX(Math.PI / 2)
  ];
  var coralBuckets = [[], [], [], []];

  function plantReef(count, rMin, rMax, y, yJitter, palette) {
    for (var i = 0; i < count; i++) {
      var a = rand(0, TAU);
      var r = rand(rMin, rMax);
      var b = i % 4;
      coralBuckets[b].push({
        x: Math.cos(a) * r,
        y: y + rand(-yJitter, yJitter),
        z: Math.sin(a) * r,
        s: rand(0.7, 2.4),
        ry: rand(0, TAU),
        rz: rand(-0.35, 0.35),
        c: palette[(Math.random() * palette.length) | 0]
      });
    }
  }

  var REEF_BRIGHT = [0xff7a5c, 0xffc46b, 0xff9ec2, 0x7be0c8, 0xa06bd8, 0xf2e6b0];
  var REEF_DEEP = [0xd6624f, 0x3e9e9a, 0x7d5fa8, 0xc08a5a, 0x4f7fa8];

  plantReef(lowPower ? 60 : 130, 24, 88, -14.4, 1.6, REEF_BRIGHT);
  plantReef(lowPower ? 70 : 150, 30, 120, -24.4, 2.0, REEF_BRIGHT);
  plantReef(lowPower ? 26 : 50, 28, 64, -45, 9, REEF_DEEP);

  var dummy = new THREE.Object3D();
  var tmpColor = new THREE.Color();
  var coralMeshes = [];
  for (var cb = 0; cb < coralBuckets.length; cb++) {
    var list = coralBuckets[cb];
    if (!list.length) continue;
    var im = new THREE.InstancedMesh(CORAL_PROTOS[cb], lam(0xffffff, { emissive: 0x000000 }), list.length);
    for (var k = 0; k < list.length; k++) {
      var it = list[k];
      dummy.position.set(it.x, it.y, it.z);
      dummy.rotation.set(it.rz, it.ry, it.rz * 0.6);
      dummy.scale.setScalar(it.s);
      dummy.updateMatrix();
      im.setMatrixAt(k, dummy.matrix);
      im.setColorAt(k, tmpColor.setHex(it.c));
    }
    im.instanceMatrix.needsUpdate = true;
    if (im.instanceColor) im.instanceColor.needsUpdate = true;
    dive.add(im);
    coralMeshes.push(im);
  }

  // Bioluminescent glow corals — fade in on the night section.
  var glowCount = lowPower ? 40 : 90;
  var glowMat = new THREE.MeshBasicMaterial({ transparent: true, opacity: 0, depthWrite: false });
  var glowMesh = new THREE.InstancedMesh(new THREE.IcosahedronGeometry(0.55, 0), glowMat, glowCount);
  var GLOW_COLORS = [0x6cf3ff, 0x8affd0, 0xc59cff, 0x7fd0ff];
  for (var gi = 0; gi < glowCount; gi++) {
    var ga = rand(0, TAU), gr = rand(24, 110);
    dummy.position.set(Math.cos(ga) * gr, rand(-30, -12), Math.sin(ga) * gr);
    dummy.rotation.set(rand(0, TAU), rand(0, TAU), 0);
    dummy.scale.setScalar(rand(0.8, 2.6));
    dummy.updateMatrix();
    glowMesh.setMatrixAt(gi, dummy.matrix);
    glowMesh.setColorAt(gi, tmpColor.setHex(GLOW_COLORS[gi % GLOW_COLORS.length]));
  }
  glowMesh.instanceMatrix.needsUpdate = true;
  if (glowMesh.instanceColor) glowMesh.instanceColor.needsUpdate = true;
  dive.add(glowMesh);

  /* ---------- the three Lung Corals ---------- */
  var lungGlows = [];
  for (var li = 0; li < 3; li++) {
    var la = (li / 3) * TAU + 0.4;
    var lg = new THREE.Group();
    lg.position.set(Math.cos(la) * 24, -34 - li * 5, Math.sin(la) * 24);

    var pod = new THREE.Mesh(new THREE.IcosahedronGeometry(1.5, 1), new THREE.MeshBasicMaterial({ color: 0x7ff0e0 }));
    lg.add(pod);

    var halo = new THREE.Sprite(new THREE.SpriteMaterial({
      map: SPRITE_TEX, color: 0x6ce8ff, transparent: true, opacity: 0.85,
      blending: THREE.AdditiveBlending, depthWrite: false, fog: false
    }));
    halo.scale.setScalar(13);
    lg.add(halo);

    dive.add(lg);
    lungGlows.push({ group: lg, halo: halo, phase: li * 2.1 });
  }

  /* -----------------------------------------------------------
     Sunken temple on the abyss floor
     ----------------------------------------------------------- */
  var ruins = new THREE.Group();
  ruins.position.y = -77;
  dive.add(ruins);

  var stoneMat = lam(0x2b3f49);
  for (var si = 0; si < 3; si++) {
    var step = new THREE.Mesh(BOX, stoneMat);
    step.scale.set(34 - si * 7, 2.2, 34 - si * 7);
    step.position.y = 1.2 + si * 2.2;
    ruins.add(step);
  }
  for (var col = 0; col < 9; col++) {
    var ca = (col / 9) * TAU;
    var ch = rand(4, 15);
    var pillar = new THREE.Mesh(new THREE.CylinderGeometry(1.0, 1.25, ch, 8), stoneMat);
    pillar.position.set(Math.cos(ca) * 13, 7 + ch / 2, Math.sin(ca) * 13);
    pillar.rotation.z = rand(-0.06, 0.06);
    ruins.add(pillar);
  }
  for (var blk = 0; blk < 10; blk++) {
    var b = new THREE.Mesh(BOX, stoneMat);
    var ba = rand(0, TAU), br = rand(18, 46);
    b.scale.set(rand(2, 5), rand(1.2, 3), rand(2, 5));
    b.position.set(Math.cos(ba) * br, rand(0.5, 2), Math.sin(ba) * br);
    b.rotation.set(rand(-0.3, 0.3), rand(0, TAU), rand(-0.3, 0.3));
    ruins.add(b);
  }

  var relics = [];
  for (var rl = 0; rl < 5; rl++) {
    var relicA = rand(0, TAU), relicR = rand(6, 26);
    var relic = new THREE.Sprite(new THREE.SpriteMaterial({
      map: SPRITE_TEX, color: 0xffd27a, transparent: true, opacity: 0.9,
      blending: THREE.AdditiveBlending, depthWrite: false, fog: false
    }));
    relic.scale.setScalar(rand(5, 9));
    relic.position.set(Math.cos(relicA) * relicR, rand(8, 12), Math.sin(relicA) * relicR);
    ruins.add(relic);
    relics.push({ s: relic, phase: rand(0, TAU) });
  }

  /* -----------------------------------------------------------
     Shark
     ----------------------------------------------------------- */
  function buildShark() {
    var g = new THREE.Group();

    var body = new THREE.Mesh(new THREE.SphereGeometry(1, 14, 9), MAT.shark);
    body.scale.set(1.5, 1.7, 5.4);
    g.add(body);

    var snout = new THREE.Mesh(new THREE.ConeGeometry(1.35, 3.0, 9).rotateX(Math.PI / 2), MAT.shark);
    snout.position.z = 6.0;
    snout.scale.set(1.05, 1.15, 1);
    g.add(snout);

    var dorsal = new THREE.Mesh(new THREE.ConeGeometry(1.5, 3.2, 3), MAT.shark);
    dorsal.position.set(0, 2.1, 0.4);
    dorsal.scale.set(1, 1, 0.22);
    dorsal.rotation.y = Math.PI / 2;
    g.add(dorsal);

    for (var s = -1; s <= 1; s += 2) {
      var fin = new THREE.Mesh(new THREE.ConeGeometry(1.2, 3.4, 3), MAT.shark);
      fin.position.set(s * 1.3, -0.6, 1.2);
      fin.rotation.set(Math.PI / 2, 0, s * 1.15);
      fin.scale.set(1, 1, 0.2);
      g.add(fin);
    }

    var tail = new THREE.Group();
    var upper = new THREE.Mesh(new THREE.ConeGeometry(1.1, 4.2, 3), MAT.shark);
    upper.position.set(0, 1.5, -1.3);
    upper.rotation.set(-0.9, 0, 0);
    upper.scale.set(1, 1, 0.2);
    tail.add(upper);
    var lower = new THREE.Mesh(new THREE.ConeGeometry(0.8, 2.6, 3), MAT.shark);
    lower.position.set(0, -1.0, -1.0);
    lower.rotation.set(2.35, 0, 0);
    lower.scale.set(1, 1, 0.2);
    tail.add(lower);
    tail.position.z = -5.2;
    g.add(tail);

    g.userData.tail = tail;
    return g;
  }

  var shark = buildShark();
  shark.position.set(34, -58, 0);
  dive.add(shark);

  /* -----------------------------------------------------------
     Fish schools (instanced)
     ----------------------------------------------------------- */
  var fishCount = lowPower ? 50 : 110;
  var fishGeo = new THREE.ConeGeometry(0.42, 1.5, 4).rotateX(Math.PI / 2);
  var fishMesh = new THREE.InstancedMesh(fishGeo, lam(0xffffff), fishCount);
  var fish = [];
  var FISH_COLORS = [0xffd166, 0xff8f5c, 0x6fd6e8, 0xf0f4f7, 0xa6e36b];
  for (var fi = 0; fi < fishCount; fi++) {
    var school = fi % 3;
    fish.push({
      r: [rand(18, 38), rand(26, 52), rand(30, 70)][school],
      y: [-11, -20, -30][school] + rand(-3.5, 3.5),
      a: rand(0, TAU),
      sp: rand(0.09, 0.17) * (school === 1 ? -1 : 1),
      w: rand(0.6, 1.8),
      ph: rand(0, TAU),
      s: rand(0.7, 1.5)
    });
    fishMesh.setColorAt(fi, tmpColor.setHex(FISH_COLORS[fi % FISH_COLORS.length]));
  }
  if (fishMesh.instanceColor) fishMesh.instanceColor.needsUpdate = true;
  dive.add(fishMesh);

  /* -----------------------------------------------------------
     Bubbles + marine snow
     ----------------------------------------------------------- */
  function makePoints(count, spreadXZ, spreadY, size, color, tex, additive) {
    var positions = new Float32Array(count * 3);
    var data = [];
    for (var i = 0; i < count; i++) {
      var a = rand(0, TAU), r = Math.sqrt(Math.random()) * spreadXZ;
      var d = { x: Math.cos(a) * r, y: rand(-spreadY, spreadY), z: Math.sin(a) * r, sp: rand(0.5, 1), ph: rand(0, TAU) };
      data.push(d);
      positions[i * 3] = d.x; positions[i * 3 + 1] = d.y; positions[i * 3 + 2] = d.z;
    }
    var geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    var mat = new THREE.PointsMaterial({
      size: size, map: tex, color: color, transparent: true, opacity: 0,
      depthWrite: false, sizeAttenuation: true,
      blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending
    });
    var pts = new THREE.Points(geo, mat);
    pts.frustumCulled = false;
    scene.add(pts);
    return { pts: pts, data: data, positions: positions, spreadY: spreadY };
  }

  var bubbles = makePoints(lowPower ? 130 : 260, 26, 26, 0.55, 0xdff6ff, BUBBLE_TEX, false);
  var snow = makePoints(lowPower ? 160 : 320, 40, 34, 0.32, 0xbfe8ff, SPRITE_TEX, true);

  /* -----------------------------------------------------------
     God rays
     ----------------------------------------------------------- */
  var rayUniforms = { uOpacity: { value: 0 }, uTime: { value: 0 }, uColor: { value: new THREE.Color(0xbdf0ff) } };
  var rayMat = new THREE.ShaderMaterial({
    uniforms: rayUniforms,
    transparent: true,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
    side: THREE.DoubleSide,
    vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
    fragmentShader: [
      'uniform vec3 uColor; uniform float uOpacity; uniform float uTime;',
      'varying vec2 vUv;',
      'void main(){',
      '  float edge = smoothstep(0.0,0.30,vUv.x) * smoothstep(1.0,0.70,vUv.x);',
      '  float fade = smoothstep(0.0,0.30,vUv.y) * pow(vUv.y, 1.4);',
      '  float flick = 0.78 + 0.22 * sin(uTime*0.8 + vUv.x*9.0);',
      '  gl_FragColor = vec4(uColor, edge*fade*uOpacity*flick);',
      '}'
    ].join('\n')
  });

  var rayGeo = new THREE.PlaneGeometry(1, 1);
  var rayCount = lowPower ? 4 : 8;
  for (var rc = 0; rc < rayCount; rc++) {
    var ray = new THREE.Mesh(rayGeo, rayMat);
    var raA = (rc / rayCount) * TAU + rand(-0.2, 0.2);
    var raR = rand(16, 46);
    ray.position.set(Math.cos(raA) * raR, -28, Math.sin(raA) * raR);
    ray.scale.set(rand(7, 18), 62, 1);
    ray.lookAt(0, -28, 0);
    ray.rotateZ(rand(-0.14, 0.14));
    dive.add(ray);
  }

  /* -----------------------------------------------------------
     Colour grading by depth
     ----------------------------------------------------------- */
  var GRADE = [
    { d: -30, fog: 0xeb9f6c, den: 0.0022, top: 0x1b5590, mid: 0xff8a52, bot: 0xffd9a8, sun: 1.0, hemi: 1.0, dir: 1.35, dive: 0.0, ray: 0.0 },
    { d: -3, fog: 0xdfb188, den: 0.0042, top: 0x2a6ba6, mid: 0xff9d68, bot: 0xffe1b8, sun: 1.0, hemi: 0.95, dir: 1.25, dive: 0.0, ray: 0.25 },
    { d: 5, fog: 0x2b9cb4, den: 0.0135, top: 0x2b9cb4, mid: 0x2b9cb4, bot: 0x2b9cb4, sun: 0.75, hemi: 0.85, dir: 0.95, dive: 0.25, ray: 1.0 },
    { d: 20, fog: 0x13748f, den: 0.0205, top: 0x13748f, mid: 0x13748f, bot: 0x13748f, sun: 0.45, hemi: 0.60, dir: 0.62, dive: 0.7, ray: 0.85 },
    { d: 34, fog: 0x0a4463, den: 0.0300, top: 0x0a4463, mid: 0x0a4463, bot: 0x0a4463, sun: 0.20, hemi: 0.38, dir: 0.32, dive: 1.2, ray: 0.35 },
    { d: 55, fog: 0x041f33, den: 0.0420, top: 0x041f33, mid: 0x041f33, bot: 0x041f33, sun: 0.05, hemi: 0.22, dir: 0.12, dive: 1.6, ray: 0.05 },
    { d: 72, fog: 0x010c16, den: 0.0540, top: 0x010c16, mid: 0x010c16, bot: 0x010c16, sun: 0.0, hemi: 0.14, dir: 0.05, dive: 1.9, ray: 0.0 }
  ];

  var gradeA = {}, gradeB = {};
  var cFog = new THREE.Color(), cTop = new THREE.Color(), cMid = new THREE.Color(), cBot = new THREE.Color();
  var NIGHT_FOG = new THREE.Color(0x03101f);

  function gradeAt(depth, out) {
    var i = 0;
    while (i < GRADE.length - 2 && depth > GRADE[i + 1].d) i++;
    var a = GRADE[i], b = GRADE[i + 1];
    var t = smoothstep(a.d, b.d, depth);
    out.t = t;
    cFog.setHex(a.fog).lerp(tmpColor.setHex(b.fog), t);
    cTop.setHex(a.top).lerp(tmpColor.setHex(b.top), t);
    cMid.setHex(a.mid).lerp(tmpColor.setHex(b.mid), t);
    cBot.setHex(a.bot).lerp(tmpColor.setHex(b.bot), t);
    out.den = lerp(a.den, b.den, t);
    out.sun = lerp(a.sun, b.sun, t);
    out.hemi = lerp(a.hemi, b.hemi, t);
    out.dir = lerp(a.dir, b.dir, t);
    out.dive = lerp(a.dive, b.dive, t);
    out.ray = lerp(a.ray, b.ray, t);
    return out;
  }

  /* -----------------------------------------------------------
     State driven by the page
     ----------------------------------------------------------- */
  var state = {
    targetDepth: -16,
    depth: -16,
    targetNight: 0,
    night: 0,
    mx: 0, my: 0, tmx: 0, tmy: 0
  };
  var synced = false;

  window.IslaScene = {
    setTarget: function (depth, night) {
      state.targetDepth = depth;
      state.targetNight = night;
      // If the page opens already scrolled (a refresh, or an anchor link),
      // start at that depth instead of swooping down from the sky.
      if (!synced) { synced = true; state.depth = depth; state.night = night; }
    },
    getDepth: function () { return state.depth; },
    ready: true
  };

  /* __DEV_HOOK__ */
  window.__isla = {
    step: function (n) { for (var i = 0; i < (n || 1); i++) frame(true); },
    snap: function (d, n) { state.depth = state.targetDepth = d; state.night = state.targetNight = n || 0; }
  };
  /* __DEV_HOOK_END__ */

  if (!reduceMotion) {
    window.addEventListener('pointermove', function (e) {
      state.tmx = (e.clientX / window.innerWidth - 0.5) * 2;
      state.tmy = (e.clientY / window.innerHeight - 0.5) * 2;
    }, { passive: true });
  }

  window.addEventListener('resize', function () {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight, false);
  });

  /* -----------------------------------------------------------
     Frame loop
     ----------------------------------------------------------- */
  var grade = gradeAt(-16, {});
  var clock = new THREE.Clock();
  var aboveTarget = new THREE.Vector3(30, 19, -165);
  var underTarget = new THREE.Vector3();
  var lookTarget = new THREE.Vector3(30, 19, -165);

  var frames = 0, slowFrames = 0, degraded = false;
  var uwTint = document.getElementById('uw-tint');

  function frame() {
    requestAnimationFrame(frame);
    if (document.hidden) return;

    var dt = Math.min(clock.getDelta(), 0.05);
    var t = clock.elapsedTime;

    /* adaptive quality: drop resolution if we cannot keep up */
    if (!degraded) {
      frames++;
      if (dt > 0.032) slowFrames++;
      if (frames > 90) {
        if (slowFrames > 40 && pixelRatio > 1) {
          pixelRatio = 1;
          renderer.setPixelRatio(1);
          renderer.setSize(window.innerWidth, window.innerHeight, false);
          degraded = true;
        }
        frames = 0; slowFrames = 0;
      }
    }

    /* smooth the scroll-driven values */
    var ease = reduceMotion ? 1 : 1 - Math.pow(0.0015, dt);
    state.depth += (state.targetDepth - state.depth) * ease;
    state.night += (state.targetNight - state.night) * (reduceMotion ? 1 : 1 - Math.pow(0.02, dt));
    state.mx += (state.tmx - state.mx) * (1 - Math.pow(0.02, dt));
    state.my += (state.tmy - state.my) * (1 - Math.pow(0.02, dt));

    var depth = state.depth;
    var uw = smoothstep(-1.5, 3.5, depth);
    var night = state.night;

    /* camera */
    var drift = reduceMotion ? 0 : 1;
    var camY = -depth;
    camera.position.set(
      Math.sin(t * 0.07) * 2.6 * drift + state.mx * 4.5,
      camY + Math.sin(t * 0.5) * 0.28 * drift * uw,
      COLUMN_Z + Math.cos(t * 0.05) * 2.0 * drift - state.my * 1.5
    );
    underTarget.set(state.mx * 14, camY - 17 - uw * 6, COLUMN_Z - 48);
    lookTarget.copy(aboveTarget).lerp(underTarget, uw);
    lookTarget.y += -state.my * 8 * (1 - uw);
    camera.lookAt(lookTarget);

    sky.position.copy(camera.position);

    /* grading */
    gradeAt(depth, grade);
    var nfog = cFog.clone().lerp(NIGHT_FOG, night * 0.8 * (1 - uw * 0.2));
    scene.fog.color.copy(nfog);
    scene.fog.density = grade.den * (1 + night * 0.25);
    renderer.setClearColor(nfog, 1);

    skyUniforms.uTop.value.copy(cTop).lerp(NIGHT_FOG, night * 0.85);
    skyUniforms.uMid.value.copy(cMid).lerp(NIGHT_FOG, night * 0.85);
    skyUniforms.uBot.value.copy(cBot).lerp(NIGHT_FOG, night * 0.85);
    skyUniforms.uSun.value = grade.sun * (1 - night);

    hemi.intensity = grade.hemi * (1 - night * 0.55);
    hemi.color.copy(cMid);
    hemi.groundColor.copy(nfog);
    sunLight.intensity = grade.dir * (1 - night * 0.7);
    sunLight.position.copy(camera.position).addScaledVector(SUN_DIR, 200);

    diveLight.position.copy(camera.position);
    diveLight.intensity = grade.dive * (1 + night * 0.5);

    var sunFade = 1 - uw;
    sunCore.material.opacity = sunFade * (1 - night);
    sunHalo.material.opacity = 0.75 * sunFade * (1 - night);
    sunCore.visible = sunHalo.visible = sunFade > 0.01;

    /* water */
    waterUniforms.uTime.value = t * (reduceMotion ? 0.25 : 1);
    waterUniforms.uDeep.value.setHex(0x063a52).lerp(nfog, clamp(uw * 0.7 + night * 0.35, 0, 1));
    waterUniforms.uShallow.value.setHex(0x1fa5ae).lerp(nfog, clamp(uw * 0.6 + night * 0.4, 0, 1));
    waterUniforms.uSky.value.copy(skyUniforms.uMid.value).lerp(skyUniforms.uTop.value, 0.35);
    waterUniforms.uUnder.value.copy(nfog);
    waterUniforms.uSunCol.value.setHex(0xffd3a0).multiplyScalar(grade.sun * (1 - night) + 0.05);
    waterUniforms.uAmp.value = 1 + night * 0.15;

    /* rays */
    rayUniforms.uTime.value = t;
    rayUniforms.uOpacity.value = grade.ray * 0.30 * (1 - night * 0.8);
    rayUniforms.uColor.value.setHex(night > 0.5 ? 0x9fd6ff : 0xbdf0ff);

    /* corals: dim with depth, glow at night */
    for (var i = 0; i < coralMeshes.length; i++) {
      coralMeshes[i].material.emissive.setHex(0x0a3a44).multiplyScalar(night * 0.9);
    }
    glowMat.opacity = night * 0.95;
    glowMesh.visible = night > 0.02;

    /* lung corals pulse */
    for (var lg = 0; lg < lungGlows.length; lg++) {
      var L = lungGlows[lg];
      var pulse = 0.65 + 0.35 * Math.sin(t * 1.3 + L.phase);
      L.halo.scale.setScalar(11 + pulse * 5);
      L.halo.material.opacity = 0.35 + pulse * 0.5;
      L.group.rotation.y = t * 0.25 + L.phase;
    }
    for (var rr = 0; rr < relics.length; rr++) {
      relics[rr].s.material.opacity = 0.45 + 0.45 * Math.sin(t * 1.9 + relics[rr].phase);
    }

    /* floating boats */
    for (var fl = 0; fl < floaters.length; fl++) {
      var b = floaters[fl];
      var wy = waveAt(b.position.x, b.position.z, waterUniforms.uTime.value);
      b.position.y = wy + 0.1;
      b.rotation.z = (waveAt(b.position.x + 3, b.position.z, waterUniforms.uTime.value) - wy) * 0.35;
      b.rotation.x = (waveAt(b.position.x, b.position.z + 3, waterUniforms.uTime.value) - wy) * 0.3;
    }

    /* fish */
    if (uw > 0.02) {
      for (var f = 0; f < fish.length; f++) {
        var F = fish[f];
        F.a += F.sp * dt;
        var fx = Math.cos(F.a) * F.r;
        var fz = Math.sin(F.a) * F.r;
        var fy = F.y + Math.sin(t * F.w + F.ph) * 1.6;
        dummy.position.set(fx, fy, fz);
        dummy.lookAt(
          Math.cos(F.a + F.sp * 0.4) * F.r,
          fy + Math.sin(t * F.w + F.ph + 0.3) * 1.6,
          Math.sin(F.a + F.sp * 0.4) * F.r
        );
        dummy.scale.set(F.s * 0.55, F.s, F.s);
        dummy.updateMatrix();
        fishMesh.setMatrixAt(f, dummy.matrix);
      }
      fishMesh.instanceMatrix.needsUpdate = true;
    }
    fishMesh.visible = uw > 0.02;

    /* shark: wide patrol of the abyss */
    var sharkAng = t * 0.085;
    var sr = 33 + Math.sin(t * 0.13) * 9;
    shark.position.set(Math.cos(sharkAng) * sr, -58 + Math.sin(t * 0.21) * 4, Math.sin(sharkAng) * sr);
    shark.lookAt(
      dive.position.x + Math.cos(sharkAng + 0.25) * sr,
      dive.position.y + -58 + Math.sin(t * 0.21 + 0.2) * 4,
      dive.position.z + Math.sin(sharkAng + 0.25) * sr
    );
    shark.rotation.z += Math.sin(t * 0.4) * 0.05;
    shark.userData.tail.rotation.y = Math.sin(t * 2.2) * 0.32;

    /* particles ride along with the camera */
    updatePoints(bubbles, dt, 1, clamp(uw, 0, 1) * 0.75);
    updatePoints(snow, dt, -0.12, clamp(uw, 0, 1) * (0.25 + night * 0.65));

    /* DOM wash */
    if (uwTint) uwTint.style.opacity = (uw * 0.55 + night * 0.15).toFixed(3);

    renderer.render(scene, camera);
  }

  function updatePoints(P, dt, rise, opacity) {
    P.pts.material.opacity = opacity;
    P.pts.visible = opacity > 0.01;
    if (!P.pts.visible) return;
    P.pts.position.set(camera.position.x, camera.position.y, camera.position.z);
    var pos = P.positions;
    var t = clock.elapsedTime;
    for (var i = 0; i < P.data.length; i++) {
      var d = P.data[i];
      d.y += rise * d.sp * dt * (rise > 0 ? 6 : 3);
      if (d.y > P.spreadY) d.y = -P.spreadY;
      if (d.y < -P.spreadY) d.y = P.spreadY;
      pos[i * 3] = d.x + Math.sin(t * 0.7 + d.ph) * 0.9;
      pos[i * 3 + 1] = d.y;
      pos[i * 3 + 2] = d.z + Math.cos(t * 0.6 + d.ph) * 0.9;
    }
    P.pts.geometry.attributes.position.needsUpdate = true;
  }

  canvas.addEventListener('webglcontextlost', function (e) {
    e.preventDefault();
    root.classList.add('no-3d');
  });

  frame();
})();
