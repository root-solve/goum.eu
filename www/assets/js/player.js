(() => {
  const STAGE = document.querySelector("[data-player]");
  if (!STAGE) return;

  const els = {
    count: document.querySelectorAll("[data-track-count]"),
    title: STAGE.querySelector("[data-now-title]"),
    meta: STAGE.querySelector("[data-now-meta]"),
    play: STAGE.querySelector("[data-action='play']"),
    prev: STAGE.querySelector("[data-action='prev']"),
    next: STAGE.querySelector("[data-action='next']"),
    random: STAGE.querySelector("[data-action='random']"),
    progress: STAGE.querySelector("[data-progress]"),
    fill: STAGE.querySelector("[data-progress-fill]"),
    current: STAGE.querySelector("[data-time-current]"),
    duration: STAGE.querySelector("[data-time-duration]"),
    volume: STAGE.querySelector("[data-volume]"),
    filter: STAGE.querySelector("[data-filter]"),
    list: STAGE.querySelector("[data-playlist]"),
    status: STAGE.querySelector("[data-player-status]"),
    empty: STAGE.querySelector("[data-player-empty]"),
    audio: STAGE.querySelector("audio"),
  };

  const state = {
    tracks: [],
    filtered: [],
    index: 0,
    query: "",
    seeking: false,
  };

  const normalize = (value) =>
    String(value ?? "")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase();

  const fmt = (sec) => {
    if (!Number.isFinite(sec) || sec < 0) return "0:00";
    const m = Math.floor(sec / 60);
    const s = Math.floor(sec % 60);
    return `${m}:${String(s).padStart(2, "0")}`;
  };

  const setStatus = (msg) => {
    if (els.status) els.status.textContent = msg || "";
  };

  const updateCounts = (n) => {
    els.count.forEach((node) => {
      node.textContent = String(n);
    });
  };

  const metaLine = (track) => {
    if (!track) return "";
    const bits = [];
    if (track.year != null) bits.push(String(track.year));
    if (track.num != null) bits.push(`#${track.num}`);
    if (track.mix != null) bits.push(`mix ${track.mix}`);
    if (track.feat) bits.push(`feat. ${track.feat}`);
    if (track.retake) bits.push(`retake ${track.retake}`);
    if (track.duration_label) bits.push(track.duration_label);
    return bits.join(" · ");
  };

  const escapeHtml = (str) =>
    String(str)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;");

  const trackMatches = (track, query) => {
    if (!query) return true;
    const hay = normalize(
      [
        track.title,
        track.year,
        track.num,
        track.feat,
        track.label,
        track.file,
      ].join(" ")
    );
    return hay.includes(query);
  };

  const applyFilter = () => {
    const q = normalize(state.query.trim());
    state.filtered = state.tracks
      .map((track, index) => ({ track, index }))
      .filter(({ track }) => trackMatches(track, q));
    renderPlaylist();
    if (state.query.trim()) {
      setStatus(`${state.filtered.length} / ${state.tracks.length} morceaux`);
    } else if (state.tracks.length) {
      setStatus(`${state.tracks.length} morceaux`);
    }
  };

  const renderPlaylist = () => {
    if (!els.list) return;
    els.list.innerHTML = "";

    if (!state.filtered.length) {
      const li = document.createElement("li");
      li.className = "playlist-empty";
      li.textContent = state.tracks.length
        ? "Aucun résultat pour ce filtre."
        : "Playlist vide.";
      els.list.appendChild(li);
      return;
    }

    state.filtered.forEach(({ track, index }) => {
      const li = document.createElement("li");
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className =
        "playlist-item" + (index === state.index ? " is-active" : "");
      btn.setAttribute("data-index", String(index));
      btn.innerHTML = `
        <span class="playlist-num">${track.num != null ? String(track.num).padStart(2, "0") : "-"}</span>
        <span class="playlist-title">${escapeHtml(track.title)}</span>
        <span class="playlist-year">${track.year != null ? track.year : ""}</span>
        <span class="playlist-duration">${track.duration_label ? escapeHtml(track.duration_label) : "-"}</span>
      `;
      btn.addEventListener("click", () => load(index, true));
      li.appendChild(btn);
      els.list.appendChild(li);
    });
  };

  const syncNow = () => {
    const track = state.tracks[state.index];
    if (!track) {
      if (els.title) els.title.textContent = "-";
      if (els.meta) els.meta.textContent = "";
      return;
    }
    if (els.title) els.title.textContent = track.title;
    if (els.meta) {
      els.meta.innerHTML = metaLine(track)
        .split(" · ")
        .map((part, idx) =>
          idx === 0
            ? `<span class="accent">${escapeHtml(part)}</span>`
            : escapeHtml(part)
        )
        .join(" · ");
    }
    els.list?.querySelectorAll(".playlist-item").forEach((btn) => {
      const i = Number(btn.getAttribute("data-index"));
      btn.classList.toggle("is-active", i === state.index);
    });
    const active = els.list?.querySelector(".playlist-item.is-active");
    active?.scrollIntoView({ block: "nearest", behavior: "smooth" });
  };

  const setPlayingUi = (playing) => {
    if (!els.play) return;
    els.play.setAttribute("aria-pressed", playing ? "true" : "false");
    els.play.textContent = playing ? "Pause" : "Play";
  };

  const safeMediaUrl = (url) => {
    try {
      const u = new URL(String(url || ""), window.location.origin);
      if (u.origin !== window.location.origin) return null;
      if (!u.pathname.startsWith("/mp3/")) return null;
      if (u.pathname.includes("..")) return null;
      return u.pathname + u.search;
    } catch {
      return null;
    }
  };

  const load = (index, autoplay = false) => {
    if (!state.tracks.length) return;
    state.index =
      ((index % state.tracks.length) + state.tracks.length) %
      state.tracks.length;
    const track = state.tracks[state.index];
    const src = safeMediaUrl(track.url);
    if (!src) {
      setStatus("Fichier audio invalide.");
      setPlayingUi(false);
      return;
    }
    els.audio.src = src;
    els.audio.load();
    syncNow();
    if (autoplay) {
      els.audio
        .play()
        .then(() => setPlayingUi(true))
        .catch(() => setPlayingUi(false));
    } else {
      setPlayingUi(false);
    }
  };

  const queue = () =>
    state.filtered.length
      ? state.filtered.map((item) => item.index)
      : state.tracks.map((_, i) => i);

  const step = (delta) => {
    const list = queue();
    if (!list.length) return;
    const pos = list.indexOf(state.index);
    const from = pos === -1 ? 0 : pos;
    const next = list[(from + delta + list.length) % list.length];
    load(next, true);
  };

  const toggle = () => {
    if (!state.tracks.length) return;
    if (els.audio.paused) {
      els.audio
        .play()
        .then(() => setPlayingUi(true))
        .catch(() => setPlayingUi(false));
    } else {
      els.audio.pause();
      setPlayingUi(false);
    }
  };

  const randomTrack = () => {
    const list = queue();
    if (!list.length) return;
    if (list.length === 1) {
      load(list[0], true);
      return;
    }
    let next = state.index;
    while (next === state.index || !list.includes(next)) {
      next = list[Math.floor(Math.random() * list.length)];
    }
    load(next, true);
  };

  const seekFromEvent = (event) => {
    if (!Number.isFinite(els.audio.duration) || els.audio.duration <= 0) return;
    const rect = els.progress.getBoundingClientRect();
    const x =
      ("touches" in event ? event.touches[0].clientX : event.clientX) -
      rect.left;
    const ratio = Math.min(1, Math.max(0, x / rect.width));
    els.audio.currentTime = ratio * els.audio.duration;
    els.fill.style.width = `${ratio * 100}%`;
  };

  const bind = () => {
    els.play?.addEventListener("click", toggle);
    els.prev?.addEventListener("click", () => step(-1));
    els.next?.addEventListener("click", () => step(1));
    els.random?.addEventListener("click", randomTrack);

    els.filter?.addEventListener("input", () => {
      state.query = els.filter.value || "";
      applyFilter();
    });

    els.audio.addEventListener("timeupdate", () => {
      if (state.seeking) return;
      const { currentTime, duration } = els.audio;
      if (els.current) els.current.textContent = fmt(currentTime);
      if (els.duration) els.duration.textContent = fmt(duration);
      if (Number.isFinite(duration) && duration > 0) {
        els.fill.style.width = `${(currentTime / duration) * 100}%`;
      }
    });

    els.audio.addEventListener("ended", () => step(1));
    els.audio.addEventListener("play", () => setPlayingUi(true));
    els.audio.addEventListener("pause", () => setPlayingUi(false));
    els.audio.addEventListener("error", () => {
      setStatus("Impossible de lire ce fichier.");
      setPlayingUi(false);
    });

    els.volume?.addEventListener("input", () => {
      els.audio.volume = Number(els.volume.value);
    });

    const onDown = (event) => {
      state.seeking = true;
      seekFromEvent(event);
    };
    const onMove = (event) => {
      if (!state.seeking) return;
      seekFromEvent(event);
    };
    const onUp = () => {
      state.seeking = false;
    };

    els.progress?.addEventListener("mousedown", onDown);
    els.progress?.addEventListener("touchstart", onDown, { passive: true });
    window.addEventListener("mousemove", onMove);
    window.addEventListener("touchmove", onMove, { passive: true });
    window.addEventListener("mouseup", onUp);
    window.addEventListener("touchend", onUp);

    els.progress?.addEventListener("keydown", (event) => {
      if (!Number.isFinite(els.audio.duration)) return;
      const stepSec = event.shiftKey ? 10 : 5;
      if (event.key === "ArrowRight") {
        els.audio.currentTime = Math.min(
          els.audio.duration,
          els.audio.currentTime + stepSec
        );
        event.preventDefault();
      } else if (event.key === "ArrowLeft") {
        els.audio.currentTime = Math.max(0, els.audio.currentTime - stepSec);
        event.preventDefault();
      }
    });
  };

  const init = async () => {
    bind();
    if (els.volume) els.audio.volume = Number(els.volume.value);
    setStatus("Chargement de la playlist…");
    try {
      const res = await fetch("/api/tracks", { cache: "no-store" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      state.tracks = Array.isArray(data.tracks) ? data.tracks : [];
      updateCounts(data.count ?? state.tracks.length);

      if (!state.tracks.length) {
        STAGE.classList.add("is-empty");
        if (els.empty) els.empty.hidden = false;
        setStatus("");
        els.play && (els.play.disabled = true);
        els.prev && (els.prev.disabled = true);
        els.next && (els.next.disabled = true);
        els.random && (els.random.disabled = true);
        els.filter && (els.filter.disabled = true);
        return;
      }

      if (els.empty) els.empty.hidden = true;
      applyFilter();
      load(0, false);
    } catch (err) {
      console.error(err);
      updateCounts(0);
      setStatus("Playlist indisponible.");
      if (els.empty) {
        els.empty.hidden = false;
        els.empty.textContent = "Impossible de charger /api/tracks.";
      }
    }
  };

  init();
})();
