(function () {
  var cfg = window.hearthIntranet || {};

  function el(id) {
    return document.getElementById(id);
  }

  function empty(node, text) {
    if (!node) return;
    node.hidden = false;
    node.innerHTML = "<h2></h2><p class=\"empty\"></p>";
    node.querySelector("h2").textContent = node.id;
    node.querySelector("p").textContent = text;
  }

  function heading(node, title) {
    var h = document.createElement("h2");
    h.textContent = title;
    node.appendChild(h);
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

  function fmtClock(iso) {
    if (!iso) return "—";
    return new Date(iso).toLocaleTimeString(undefined, {
      hour: "numeric",
      minute: "2-digit",
    });
  }

  function renderWeather() {
    var node = el("weather");
    if (!node) return;
    if (cfg.latitude == null || cfg.longitude == null) {
      empty(node, "set lat/lon in intranet-config.nix");
      return;
    }
    var url =
      "https://api.open-meteo.com/v1/forecast?latitude=" +
      encodeURIComponent(cfg.latitude) +
      "&longitude=" +
      encodeURIComponent(cfg.longitude) +
      "&current=temperature_2m,weather_code,wind_speed_10m" +
      "&daily=sunrise,sunset&timezone=auto";
    fetch(url)
      .then(function (res) {
        if (!res.ok) throw new Error("open-meteo " + res.status);
        return res.json();
      })
      .then(function (data) {
        node.hidden = false;
        node.innerHTML = "";
        heading(node, "Weather");
        var cur = data.current || {};
        var daily = data.daily || {};
        var p = document.createElement("p");
        p.textContent =
          Math.round(cur.temperature_2m) +
          "° · " +
          weatherLabel(cur.weather_code) +
          " · wind " +
          Math.round(cur.wind_speed_10m) +
          " · sunrise " +
          fmtClock(daily.sunrise && daily.sunrise[0]) +
          " · sunset " +
          fmtClock(daily.sunset && daily.sunset[0]);
        node.appendChild(p);
      })
      .catch(function () {
        empty(node, "weather unavailable");
      });
  }

  function renderTransit() {
    var node = el("transit");
    if (!node) return;
    var from = (cfg.routeFrom || "").trim();
    var to = (cfg.routeTo || "").trim();
    if (!from || !to) {
      empty(node, "set routeFrom / routeTo in intranet-config.nix");
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

  function renderBuses() {
    var node = el("transit-buses") || el("buses");
    var host = node || el("transit");
    // BUS_ENDPOINT: no public agency JSON is configured (no Bitwarden key).
    // When Nick names a GTFS/agency URL, fetch it here with cfg.busStopIds.
    var mounts = el("transit");
    if (!mounts) return;
    var stops = cfg.busStopIds || [];
    var bus = document.createElement("div");
    bus.id = "buses";
    if (!stops.length) {
      bus.innerHTML = "<p class=\"empty\">add stop IDs in intranet-config.nix</p>";
    } else {
      bus.innerHTML =
        "<p class=\"empty\">bus stop IDs are set, but no agency endpoint is wired yet</p>";
    }
    mounts.appendChild(bus);
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
    if (!cfg.calendarIcsUrl) {
      draw({});
      return;
    }
    fetch(cfg.calendarIcsUrl)
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

  function renderHealth(data) {
    var node = el("health");
    if (!node) return;
    node.hidden = false;
    node.innerHTML = "";
    heading(node, "Health");
    var ul = document.createElement("ul");
    ul.className = "health";
    function row(label, value) {
      var li = document.createElement("li");
      li.textContent = label + ": " + value;
      ul.appendChild(li);
    }
    if (!data) {
      row("status", "unavailable");
      node.appendChild(ul);
      return;
    }
    var root = data.root || {};
    row("root", (root.usedPercent != null ? root.usedPercent + "% used" : "—") + (root.avail ? " · " + root.avail + " free" : ""));
    var cold = data.cold || {};
    if (cold.mounted) {
      row("cold", (cold.usedPercent != null ? cold.usedPercent + "% used" : "—") + (cold.avail ? " · " + cold.avail + " free" : ""));
    } else {
      row("cold", "unplugged");
    }
    if (data.battery) {
      var st = data.battery.status || "unknown";
      var plug = st === "charging" || st === "full" ? "AC" : "battery";
      row("battery", data.battery.percent + "% · " + plug);
    } else {
      row("battery", "none");
    }
    row("Pi-hole", "Pi-hole not on the LAN yet");
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
