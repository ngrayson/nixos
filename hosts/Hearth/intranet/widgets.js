(function () {
  var cfg = window.hearthIntranet || {};

  function widget(name) {
    return cfg[name] || {};
  }

  function el(id) {
    return document.getElementById(id);
  }

  // Nerd Font Symbols (hex codepoints). See nerd-fonts glyphnames.json.
  var ICO = {
    weather: "f0595", // md-weather_partly_cloudy
    sunny: "e30d",
    overcast: "e30c",
    cloudy: "e312",
    fog: "e313",
    drizzle: "e31b",
    rain: "e318",
    showers: "e319",
    snow: "e31a",
    thunder: "e31d",
    thermometer: "e350",
    wind: "e31e",
    sunrise: "e34c",
    sunset: "e34d",
    moonrise: "e3c1",
    moonset: "e3c2",
    aci: "e35d", // weather-dust
    disk: "f02ca", // md-harddisk
    hdd: "f02ca",
    hddOff: "f104c", // md-harddisk_remove
    battery: "f0079",
    batteryOff: "f008e",
    bus: "f00e7", // md-bus
  };

  function nfChar(code) {
    return String.fromCodePoint(parseInt(code, 16));
  }

  function iconEl(code) {
    var s = document.createElement("span");
    s.className = "nf";
    s.setAttribute("aria-hidden", "true");
    s.textContent = nfChar(code);
    return s;
  }

  function empty(node, text, title, code) {
    if (!node) return;
    node.hidden = false;
    node.innerHTML = "";
    heading(node, title || node.id, code);
    var p = document.createElement("p");
    p.className = "empty";
    p.textContent = text;
    node.appendChild(p);
  }

  function heading(node, title, code) {
    var h = document.createElement("h2");
    if (code) {
      h.appendChild(iconEl(code));
      h.appendChild(document.createTextNode(" " + title));
    } else {
      h.textContent = title;
    }
    node.appendChild(h);
  }

  function fact(parent, code, text) {
    var span = document.createElement("span");
    span.className = "fact";
    span.appendChild(iconEl(code));
    span.appendChild(document.createTextNode(text));
    parent.appendChild(span);
  }

  function weatherLabel(code) {
    if (code === 0) return "Clear";
    if (code <= 3) return "Cloudy";
    if (code === 45 || code === 48) return "Fog";
    if (code >= 51 && code <= 67) return "Rain";
    if (code >= 71 && code <= 77) return "Snow";
    if (code >= 80 && code <= 82) return "Showers";
    if (code >= 95) return "Thunder";
    return "Weather " + code;
  }

  function weatherIcon(code) {
    if (code === 0) return ICO.sunny;
    if (code === 1) return ICO.overcast;
    if (code <= 3) return ICO.cloudy;
    if (code === 45 || code === 48) return ICO.fog;
    if (code >= 51 && code <= 55) return ICO.drizzle;
    if (code >= 56 && code <= 67) return ICO.rain;
    if (code >= 71 && code <= 77) return ICO.snow;
    if (code >= 80 && code <= 82) return ICO.showers;
    if (code >= 85 && code <= 86) return ICO.snow;
    if (code >= 95) return ICO.thunder;
    return ICO.cloudy;
  }

  function moonPhase(frac) {
    var phases = [
      { code: "e38d", label: "New moon" },
      { code: "e390", label: "Waxing crescent" },
      { code: "e394", label: "First quarter" },
      { code: "e397", label: "Waxing gibbous" },
      { code: "e39b", label: "Full moon" },
      { code: "e39e", label: "Waning gibbous" },
      { code: "e3a2", label: "Last quarter" },
      { code: "e3a5", label: "Waning crescent" },
    ];
    if (frac == null || isNaN(frac)) return phases[0];
    var t = ((Number(frac) % 1) + 1) % 1;
    return phases[Math.round(t * 8) % 8];
  }

  function batteryIcon(percent) {
    if (percent == null || isNaN(percent)) return ICO.batteryOff;
    var n = Number(percent);
    if (n >= 95) return "f0079";
    if (n >= 85) return "f0082";
    if (n >= 75) return "f0081";
    if (n >= 65) return "f0080";
    if (n >= 55) return "f007f";
    if (n >= 45) return "f007e";
    if (n >= 35) return "f007d";
    if (n >= 25) return "f007c";
    if (n >= 15) return "f007b";
    if (n >= 5) return "f007a";
    return ICO.batteryOff;
  }

  function fmtClock(iso) {
    if (!iso) return "—";
    return new Date(iso).toLocaleTimeString(undefined, {
      hour: "numeric",
      minute: "2-digit",
    });
  }

  function tempUnit(weather) {
    var u = String(weather.temperatureUnit || "F").toUpperCase();
    return u === "C" ? "C" : "F";
  }

  function fetchJson(url) {
    return fetch(url).then(function (res) {
      if (!res.ok) throw new Error(url + " " + res.status);
      return res.json();
    });
  }

  function loadPlace(loc, unit) {
    var temp = unit === "C" ? "celsius" : "fahrenheit";
    var wind = unit === "C" ? "kmh" : "mph";
    var forecast =
      "https://api.open-meteo.com/v1/forecast?latitude=" +
      encodeURIComponent(loc.latitude) +
      "&longitude=" +
      encodeURIComponent(loc.longitude) +
      "&current=temperature_2m,weather_code,wind_speed_10m" +
      "&daily=sunrise,sunset,moonrise,moonset,moon_phase" +
      "&temperature_unit=" +
      temp +
      "&wind_speed_unit=" +
      wind +
      "&timezone=auto";
    var air =
      "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=" +
      encodeURIComponent(loc.latitude) +
      "&longitude=" +
      encodeURIComponent(loc.longitude) +
      "&current=us_aqi&timezone=auto";
    return Promise.all([fetchJson(forecast), fetchJson(air)]).then(function (pair) {
      return { loc: loc, forecast: pair[0], air: pair[1] };
    });
  }

  function renderPlace(node, place, unit) {
    var cur = (place.forecast && place.forecast.current) || {};
    var daily = (place.forecast && place.forecast.daily) || {};
    var aqi = place.air && place.air.current ? place.air.current.us_aqi : null;
    var phase = moonPhase(daily.moon_phase && daily.moon_phase[0]);
    var article = document.createElement("article");
    var h = document.createElement("h3");
    h.textContent = place.loc.name || "Location";
    article.appendChild(h);

    var summary = document.createElement("p");
    summary.className = "facts";
    fact(summary, ICO.thermometer, Math.round(cur.temperature_2m) + "°" + unit);
    fact(summary, weatherIcon(cur.weather_code), weatherLabel(cur.weather_code));
    fact(summary, ICO.wind, String(Math.round(cur.wind_speed_10m)));
    article.appendChild(summary);

    var sun = document.createElement("p");
    sun.className = "facts";
    fact(sun, ICO.sunrise, fmtClock(daily.sunrise && daily.sunrise[0]));
    fact(sun, ICO.sunset, fmtClock(daily.sunset && daily.sunset[0]));
    article.appendChild(sun);

    var moon = document.createElement("p");
    moon.className = "facts";
    fact(moon, phase.code, phase.label);
    fact(moon, ICO.moonrise, fmtClock(daily.moonrise && daily.moonrise[0]));
    fact(moon, ICO.moonset, fmtClock(daily.moonset && daily.moonset[0]));
    article.appendChild(moon);

    var aci = document.createElement("p");
    aci.className = "facts";
    fact(aci, ICO.aci, "ACI " + (aqi == null ? "—" : aqi));
    article.appendChild(aci);
    node.appendChild(article);
  }

  function renderWeather() {
    var node = el("weather");
    if (!node) return;
    var weather = widget("weather");
    var locations = weather.locations || [];
    var valid = locations.filter(function (loc) {
      return loc && loc.latitude != null && loc.longitude != null;
    });
    if (!valid.length) {
      empty(node, "set locations in intranet/config/weather/config.example.nix", "Weather", ICO.weather);
      return;
    }
    var unit = tempUnit(weather);
    Promise.all(
      valid.map(function (loc) {
        return loadPlace(loc, unit);
      })
    )
      .then(function (places) {
        node.hidden = false;
        node.innerHTML = "";
        heading(node, "Weather", ICO.weather);
        places.forEach(function (place) {
          renderPlace(node, place, unit);
        });
      })
      .catch(function () {
        empty(node, "weather unavailable", "Weather", ICO.weather);
      });
  }

  function renderTransit() {
    var node = el("transit");
    if (!node) return;
    var transit = widget("transit");
    var from = (transit.routeFrom || "").trim();
    var to = (transit.routeTo || "").trim();
    if (!from || !to) {
      empty(node, "set routeFrom / routeTo in intranet/config/transit/config.example.nix", "Transit");
      return;
    }
    node.hidden = false;
    node.innerHTML = "";
    heading(node, "Transit");
    var query = from + " to " + to;
    var a = document.createElement("a");
    a.className = "cta";
    a.target = "_blank";
    a.rel = "noopener";
    a.href = "https://www.openstreetmap.org/search?query=" + encodeURIComponent(query);
    a.textContent = from + " → " + to;
    node.appendChild(a);
    var note = document.createElement("p");
    note.className = "empty";
    note.textContent = "OpenStreetMap directions — live congestion is out of scope.";
    node.appendChild(note);
  }

  function configuredStops(transit) {
    var raw = transit.busStops;
    if (!Array.isArray(raw) || !raw.length) {
      raw = (transit.busStopIds || []).map(function (id) {
        return { id: id };
      });
    }
    return raw
      .map(function (s) {
        var posted = typeof s === "string" ? s : String((s && (s.id || s.stopId)) || "");
        var name = typeof s === "string" ? "" : (s && s.name) || "";
        if (!posted) return null;
        return {
          id: posted,
          obaId: posted.indexOf("_") >= 0 ? posted : "1_" + posted,
          name: name,
        };
      })
      .filter(Boolean);
  }

  function arrivalMs(row) {
    var pred = Number(row.predictedArrivalTime || 0);
    if (pred > 0) return pred;
    return Number(row.scheduledArrivalTime || 0);
  }

  function minutesAway(row, nowMs) {
    var t = arrivalMs(row);
    if (!t) return null;
    return Math.round((t - nowMs) / 60000);
  }

  function stopName(data, id) {
    var refs = (((data || {}).references || {}).stops) || [];
    var i;
    for (i = 0; i < refs.length; i++) {
      if (refs[i].id === id) return refs[i].name || id;
    }
    return id;
  }

  function renderBuses() {
    // BUS_ENDPOINT: Caddy /transit/oba/* → api.pugetsound.onebusaway.org
    //   /api/where/arrivals-and-departures-for-stop/{id}.json?key=…
    var mounts = el("transit");
    if (!mounts) return;
    var transit = widget("transit");
    var stops = configuredStops(transit);
    var bus = document.createElement("div");
    bus.id = "buses";
    mounts.appendChild(bus);

    var list = document.createElement("div");
    list.className = "bus-list";
    bus.appendChild(list);

    if (!stops.length) {
      list.innerHTML =
        "<p class=\"empty\">add busStops in intranet/config/transit/config.example.nix</p>";
      return;
    }

    var pollMs = Number(transit.obaPollSeconds || 60) * 1000;
    if (!(pollMs >= 60000)) pollMs = 60000;

    var poll = document.createElement("div");
    poll.className = "poll";
    var pollLabel = document.createElement("div");
    pollLabel.className = "poll-label";
    pollLabel.appendChild(iconEl(ICO.bus));
    pollLabel.appendChild(document.createTextNode("Schedule"));
    var track = document.createElement("div");
    track.className = "poll-track";
    var fill = document.createElement("div");
    fill.className = "poll-fill";
    track.appendChild(fill);
    var pollValue = document.createElement("div");
    pollValue.className = "poll-value";
    poll.appendChild(pollLabel);
    poll.appendChild(track);
    poll.appendChild(pollValue);
    bus.appendChild(poll);

    var awaiting = false;
    var nextAt = 0;

    function setPollUi() {
      if (awaiting) {
        poll.classList.add("is-awaiting");
        fill.style.width = "100%";
        pollValue.textContent = "awaiting response";
        return;
      }
      poll.classList.remove("is-awaiting");
      var left = Math.max(0, nextAt - Date.now());
      var pct = nextAt ? Math.max(0, Math.min(100, (left / pollMs) * 100)) : 0;
      fill.style.width = pct + "%";
      pollValue.textContent = "refresh in " + Math.ceil(left / 1000) + "s";
    }

    function draw(results) {
      list.innerHTML = "";
      var limited = results.some(function (r) {
        return r.status === 429 || (r.data && r.data.code === 429);
      });
      if (limited) {
        var rate = document.createElement("p");
        rate.className = "empty";
        rate.textContent = "rate limited — waiting to try again";
        list.appendChild(rate);
      }
      results.forEach(function (r) {
        if (r.status === 429 || (r.data && r.data.code === 429)) return;
        var wrap = document.createElement("div");
        wrap.className = "bus-stop";
        var h = document.createElement("h3");
        h.textContent =
          r.name || (r.data ? stopName(r.data.data, r.obaId || r.id) : r.id);
        wrap.appendChild(h);
        if (!r.ok || !r.data || r.data.code !== 200) {
          var miss = document.createElement("p");
          miss.className = "empty";
          miss.textContent = r.status === 404 || (r.data && r.data.code === 404) ? "stop not found" : "arrivals unavailable";
          wrap.appendChild(miss);
          list.appendChild(wrap);
          return;
        }
        var nowMs = r.data.currentTime || Date.now();
        var rows = ((r.data.data || {}).entry || {}).arrivalsAndDepartures || [];
        rows = rows.slice().sort(function (a, b) {
          return arrivalMs(a) - arrivalMs(b);
        }).slice(0, 6);
        if (!rows.length) {
          var none = document.createElement("p");
          none.className = "empty";
          none.textContent = "no arrivals in the next hour";
          wrap.appendChild(none);
          list.appendChild(wrap);
          return;
        }
        var ul = document.createElement("ul");
        ul.className = "arrivals";
        rows.forEach(function (row) {
          var li = document.createElement("li");
          var left = document.createElement("span");
          var route = document.createElement("span");
          route.className = "route";
          route.textContent = row.routeShortName || "?";
          left.appendChild(route);
          left.appendChild(document.createTextNode(" " + (row.tripHeadsign || "")));
          var mins = minutesAway(row, nowMs);
          var right = document.createElement("span");
          right.className = "mins";
          if (mins == null) right.textContent = "—";
          else if (mins <= 0) right.textContent = "due";
          else right.textContent = mins + " min" + (row.predicted ? "" : " sched");
          li.appendChild(left);
          li.appendChild(right);
          ul.appendChild(li);
        });
        wrap.appendChild(ul);
        list.appendChild(wrap);
      });
    }

    function fetchStop(stop) {
      return fetch(
        "/transit/oba/arrivals-and-departures-for-stop/" +
          encodeURIComponent(stop.obaId) +
          ".json?minutesAfter=60"
      )
        .then(function (res) {
          return res.json().then(function (data) {
            return {
              id: stop.id,
              obaId: stop.obaId,
              name: stop.name,
              ok: res.ok,
              status: res.status,
              data: data,
            };
          });
        })
        .catch(function () {
          return {
            id: stop.id,
            obaId: stop.obaId,
            name: stop.name,
            ok: false,
            status: 0,
            data: null,
          };
        });
    }

    function tick() {
      if (awaiting) return;
      awaiting = true;
      setPollUi();
      Promise.all(stops.map(fetchStop))
        .then(draw)
        .finally(function () {
          awaiting = false;
          nextAt = Date.now() + pollMs;
          setPollUi();
        });
    }

    tick();
    setInterval(function () {
      if (!awaiting && nextAt && Date.now() >= nextAt) tick();
    }, 1000);
    setInterval(setPollUi, 250);
  }

  function monthGrid(marked) {
    var now = new Date();
    var year = now.getFullYear();
    var month = now.getMonth();
    var first = new Date(year, month, 1);
    var startPad = first.getDay();
    var days = new Date(year, month + 1, 0).getDate();
    var table = document.createElement("table");
    table.className = "cal";
    var head = document.createElement("tr");
    ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].forEach(function (d) {
      var th = document.createElement("th");
      th.textContent = d;
      head.appendChild(th);
    });
    table.appendChild(head);
    var tr = document.createElement("tr");
    var i;
    for (i = 0; i < startPad; i++) {
      tr.appendChild(document.createElement("td"));
    }
    for (i = 1; i <= days; i++) {
      if (tr.children.length === 7) {
        table.appendChild(tr);
        tr = document.createElement("tr");
      }
      var td = document.createElement("td");
      var key =
        year +
        "-" +
        String(month + 1).padStart(2, "0") +
        "-" +
        String(i).padStart(2, "0");
      td.textContent = String(i);
      if (i === now.getDate()) td.className = "today";
      if (marked && marked[key]) td.className += " marked";
      tr.appendChild(td);
    }
    table.appendChild(tr);
    return table;
  }

  function parseIcsDays(text) {
    var marked = {};
    var re = /DTSTART(?:;VALUE=DATE)?:(\d{8})/g;
    var m;
    while ((m = re.exec(text))) {
      marked[m[1].slice(0, 4) + "-" + m[1].slice(4, 6) + "-" + m[1].slice(6, 8)] = true;
    }
    return marked;
  }

  function renderCalendar() {
    var node = el("calendar");
    if (!node) return;
    node.hidden = false;
    node.innerHTML = "";
    heading(node, "Calendar");
    function draw(marked) {
      var cap = document.createElement("p");
      cap.textContent = new Date().toLocaleString(undefined, {
        month: "long",
        year: "numeric",
      });
      node.appendChild(cap);
      node.appendChild(monthGrid(marked || {}));
    }
    var ics = widget("calendar").calendarIcsUrl;
    if (!ics) {
      draw({});
      return;
    }
    fetch(ics)
      .then(function (res) {
        if (!res.ok) throw new Error("ics " + res.status);
        return res.text();
      })
      .then(function (text) {
        draw(parseIcsDays(text));
      })
      .catch(function () {
        draw({});
      });
  }

  function isImage(name) {
    return /\.(jpe?g|png|gif|webp|avif)$/i.test(name);
  }

  function renderGallery() {
    var node = el("gallery");
    if (!node) return;
    fetch("/gallery/", { headers: { Accept: "text/html" } })
      .then(function (res) {
        if (!res.ok) throw new Error("gallery " + res.status);
        return res.text();
      })
      .then(function (html) {
        var docs = new DOMParser().parseFromString(html, "text/html");
        var hrefs = [];
        Array.prototype.forEach.call(docs.querySelectorAll("a[href]"), function (a) {
          var href = a.getAttribute("href");
          if (!href || href === "../" || href.slice(-1) === "/") return;
          var name = href.split("/").pop();
          if (isImage(name)) hrefs.push("/gallery/" + name);
        });
        if (!hrefs.length) {
          node.hidden = true;
          node.innerHTML = "";
          return;
        }
        node.hidden = false;
        node.innerHTML = "";
        heading(node, "Gallery");
        var img = document.createElement("img");
        img.alt = "";
        node.appendChild(img);
        var i = 0;
        function show() {
          img.src = hrefs[i % hrefs.length];
          i += 1;
        }
        show();
        setInterval(show, 12000);
      })
      .catch(function () {
        node.hidden = true;
        node.innerHTML = "";
      });
  }

  function meter(label, percent, detail, opts) {
    opts = opts || {};
    var wrap = document.createElement("div");
    wrap.className = "meter";
    var lab = document.createElement("div");
    lab.className = "meter-label";
    if (opts.icon) lab.appendChild(iconEl(opts.icon));
    lab.appendChild(document.createTextNode(label));
    wrap.appendChild(lab);
    if (!opts.hideBar) {
      var track = document.createElement("div");
      track.className = "meter-track";
      var fill = document.createElement("div");
      fill.className = "meter-fill";
      var pct = percent == null ? 0 : Math.max(0, Math.min(100, Number(percent)));
      if (opts.off) {
        fill.classList.add("is-off");
        fill.style.width = "0%";
      } else {
        fill.style.width = pct + "%";
      }
      track.appendChild(fill);
      wrap.appendChild(track);
    }
    var val = document.createElement("div");
    val.className = "meter-value";
    val.textContent = detail;
    wrap.appendChild(val);
    return wrap;
  }

  function renderHealth(data) {
    var node = el("health");
    if (!node) return;
    node.hidden = false;
    node.innerHTML = "";
    heading(node, "Server Status");
    if (!data) {
      var miss = document.createElement("p");
      miss.className = "empty";
      miss.textContent = "unavailable";
      node.appendChild(miss);
      return;
    }
    var root = data.root || {};
    var diskDetail =
      (root.usedPercent != null ? root.usedPercent + "%" : "—") +
      (root.avail ? " · " + root.avail + " free" : "");
    node.appendChild(
      meter("Disk usage", root.usedPercent, diskDetail, {
        icon: ICO.disk,
        off: root.usedPercent == null,
      })
    );

    var cold = data.cold || {};
    if (cold.mounted) {
      var hddDetail =
        (cold.usedPercent != null ? cold.usedPercent + "%" : "—") +
        (cold.avail ? " · " + cold.avail + " free" : "");
      node.appendChild(
        meter("HDD status", cold.usedPercent, hddDetail, {
          icon: ICO.hdd,
          off: cold.usedPercent == null,
        })
      );
    } else {
      node.appendChild(
        meter("HDD status", 0, "unplugged", {
          icon: ICO.hddOff,
          hideBar: true,
        })
      );
    }

    if (data.battery && data.battery.percent != null) {
      node.appendChild(
        meter("Battery", data.battery.percent, data.battery.percent + "%", {
          icon: batteryIcon(data.battery.percent),
        })
      );
    } else {
      node.appendChild(
        meter("Battery", 0, "none", {
          icon: ICO.batteryOff,
          hideBar: true,
        })
      );
    }

    var ul = document.createElement("ul");
    ul.className = "health";
    var li = document.createElement("li");
    li.textContent = "Pi-hole: Pi-hole not on the LAN yet";
    ul.appendChild(li);
    node.appendChild(ul);
  }

  function pollHealth() {
    fetch("/status.json")
      .then(function (res) {
        if (!res.ok) throw new Error("status " + res.status);
        return res.json();
      })
      .then(renderHealth)
      .catch(function () {
        renderHealth(null);
      });
  }

  renderWeather();
  renderTransit();
  renderBuses();
  renderCalendar();
  renderGallery();
  pollHealth();
  setInterval(pollHealth, 60000);
})();
