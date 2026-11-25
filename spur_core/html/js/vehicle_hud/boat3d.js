// Boat mode for the 3D dial: the compass card (layout: boat.js, shared with the 2D dial; the trim gauge is one of the
// extra gauges). A shader quad like the aircraft tapes: the card is a heading uniform, the letters come from the
// aircraft layer's glyph texture, so nothing is redrawn or uploaded while under way.
import * as THREE from 'three';
import { CHARS, LIB, VERT, f } from './air3d.js';
import { COMPASS } from './boat.js';
import { advance } from './air.js';

const G = (ch) => f(CHARS.indexOf(ch));

// the compass card's rim through its window: a point at angle phi round the card sits at x = drum sin(phi), so the
// marks crowd and narrow toward the ends; 5 deg ticks, 10 deg long ones, a label every 30 (N E S W, otherwise the
// heading in tens, as on a marine card), N in red; a fixed lubber line in the middle
function compassShader() {
  const C = COMPASS, rd = C.drum, adv = advance(C.cap);
  return `uniform float uHeading, uAlpha; varying vec2 vP;
    ${LIB}
    void main(){
      vec2 p = vP; vec2 dpx = dFdx(p), dpy = dFdy(p); float px = max(length(dpx), length(dpy));
      float win = fill(sdBox(p, vec2(${f(C.hw)}, ${f(C.hh)})), px);
      vec4 P = vec4(0.0);
      P = over(P, vec3(0.03, 0.035, 0.045), win * 0.92);
      float s = clamp(p.x / ${f(rd)}, -0.999, 0.999), phi = asin(s), k = cos(phi);
      float h = uHeading + degrees(phi);
      // ticks hang from the window's top edge
      float T = floor(h / 5.0 + 0.5) * 5.0, xt = ${f(rd)} * sin(radians(T - uHeading));
      bool ten = abs(mod(T, 10.0)) < 0.5;
      float len = ten ? 0.04 : 0.024, ytop = ${f(C.hh - 0.006)};
      float a = band(abs(p.x - xt), 0.004 * k, px) * step(ytop - len, p.y) * step(p.y, ytop);
      vec3 col = vec3(1.0);
      // labels every 30 deg
      float L = floor(h / 30.0 + 0.5) * 30.0, xl = ${f(rd)} * sin(radians(L - uHeading)), kl = cos(radians(L - uHeading));
      float m = mod(L, 360.0), tens = floor(m / 10.0 + 0.5);
      vec2 q = vec2((p.x - xl) / max(kl, 0.05), p.y + ${f(0.022)});               // card coordinates (unforeshortened)
      vec2 gx = dpx / vec2(max(kl, 0.05), 1.0), gy = dpy / vec2(max(kl, 0.05), 1.0);
      float g = 0.0; bool north = m < 0.5;
      if (m < 0.5) g = glyph(${G('N')}, 0.0, q, ${f(C.cap)}, gx, gy);
      else if (abs(m - 90.0) < 0.5) g = glyph(${G('E')}, 0.0, q, ${f(C.cap)}, gx, gy);
      else if (abs(m - 180.0) < 0.5) g = glyph(${G('S')}, 0.0, q, ${f(C.cap)}, gx, gy);
      else if (abs(m - 270.0) < 0.5) g = glyph(${G('W')}, 0.0, q, ${f(C.cap)}, gx, gy);
      else if (tens < 9.5) g = glyph(tens, 0.0, q, ${f(C.cap)}, gx, gy);
      else g = max(glyph(floor(tens / 10.0), 0.0, q + vec2(${f(adv / 2)}, 0.0), ${f(C.cap)}, gx, gy),
                   glyph(mod(tens, 10.0), 0.0, q - vec2(${f(adv / 2)}, 0.0), ${f(C.cap)}, gx, gy));
      // the card darkens as it curves away
      float shade = 0.3 + 0.7 * k;
      P = over(P, vec3(1.0) * shade, a * win);
      P = over(P, (north ? vec3(1.0, 0.35, 0.35) : vec3(1.0)) * shade, g * win * step(0.1, kl));
      // lubber line
      P = over(P, vec3(1.0, 0.55, 0.12), band(abs(p.x), 0.005, px) * win);
      // frame
      float fr = fill(sdBox(p, vec2(${f(C.hw + C.frame)}, ${f(C.hh + C.frame)})), px) * (1.0 - win);
      P = over(P, vec3(0.75), fr);
      gl_FragColor = P * uAlpha;
    }`;
}

export class Boat3D {
  constructor(parent, dig) {
    const mat = (fragmentShader, uniforms) => new THREE.ShaderMaterial({
      vertexShader: VERT, fragmentShader, transparent: true, depthWrite: false, premultipliedAlpha: true,
      uniforms: { uDig: { value: dig }, uAlpha: { value: 1 }, ...uniforms },
    });
    this.group = new THREE.Group(); parent.add(this.group);
    this.compass = mat(compassShader(), { uHeading: { value: 0 } });
    const cm = new THREE.Mesh(new THREE.PlaneGeometry(2 * (COMPASS.hw + COMPASS.frame) + 0.02, 2 * (COMPASS.hh + COMPASS.frame) + 0.02), this.compass);
    cm.position.set(0, COMPASS.y, 0.02); cm.renderOrder = 2;
    this.group.add(cm);
    this.last = {};
  }

  set visible(v) { this.group.visible = v; }

  // returns true when something visible changed
  update(s) {
    const L = this.last, hdg = s.heading || 0;
    if (L.hdg === hdg) return false;
    this.compass.uniforms.uHeading.value = hdg; L.hdg = hdg;
    return true;
  }
}
