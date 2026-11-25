# spur_loadingscreen

The loading screen for [spur_core](../spur_core) on RedM, ported from whip_loadingscreen by Whippy: the SPUR wordmark
on an 1899 backdrop, shown from the moment a player connects until they're in the world. Non-commercial and credited: Whippy allowed the port on the condition that no one makes money from it and that it
credits Whippy and WLVF.

## Features

- **The logo is the loading light.** The four circles in the bar under SPUR light up in turn, each with one of the
  interaction icons. It's the same logo, at the same size and place, as spur_core's landing page that comes next.
- **An 1899 backdrop.** A sepia ground lit like a lamp, film grain, and a printer's double rule round the edge. It's
  drawn in CSS: no WebGL and no pictures, so it shows on any machine.

## Requirements

None. It's a web page with no scripts of its own. On a spur_core server, `spur_core` closes it once the player is in
the world.

## Installation

Put `spur_loadingscreen` in your `resources` folder and add this line to `server.cfg`, after `ensure spur_core`:

```cfg
ensure spur_loadingscreen
```

Run one loading screen only. spur_core's setup report (`spursetup` in the server console) flags a second one. To use a
different loading screen, remove this one and ensure yours: spur_core closes any loading screen.

## Changing it

Open `html/index.html` in a browser to see it. The colours, the grain and the fade-in are at the top of
`html/css/loading.css`. Which icons the light shows is `NOT_1899` in `html/js/logo.js`.

## License

spur_loadingscreen is licensed under the GNU LGPL 3.0; see `COPYING.LESSER`, and `COPYING` for the GPL 3.0 it builds
on. `NOTICE.md` is whip_loadingscreen's notice with what this copy changed.
