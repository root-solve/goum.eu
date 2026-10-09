(() => {
  const deck = document.querySelector("[data-deck]");
  const swap = document.querySelector("[data-nav-swap]");
  if (!deck) return;

  const panels = [...deck.querySelectorAll(".deck-panel")];
  if (panels.length < 2) return;

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const duration = reduceMotion ? 0 : 900;
  let index = 0;
  let locked = false;
  let touchY = null;
  let wheelAcc = 0;
  let wheelTimer = 0;

  const setSwap = (onEquipe) => {
    if (!swap) return;
    if (onEquipe) {
      swap.href = "#ecoute";
      swap.textContent = "Listen";
    } else {
      swap.href = "#equipe";
      swap.textContent = "Équipe";
    }
  };

  const goTo = (next, instant = false) => {
    const clamped = Math.max(0, Math.min(panels.length - 1, next));
    if (clamped === index && !instant) return;

    index = clamped;
    locked = true;
    deck.dataset.panel = String(index);
    document.body.dataset.deckPanel = String(index);
    deck.style.setProperty("--deck-index", String(index));
    setSwap(index === 1);

    const id = panels[index]?.id;
    if (id) history.replaceState(null, "", `#${id}`);

    if (instant || reduceMotion) {
      deck.classList.add("is-instant");
      requestAnimationFrame(() => {
        deck.classList.remove("is-instant");
        locked = false;
      });
      return;
    }

    window.setTimeout(() => {
      locked = false;
      wheelAcc = 0;
    }, duration + 40);
  };

  const scrollableAncestor = (start) => {
    let node = start instanceof Element ? start : null;
    while (node && node !== document.documentElement) {
      if (node instanceof HTMLElement) {
        const style = getComputedStyle(node);
        const oy = style.overflowY;
        const canY =
          (oy === "auto" || oy === "scroll" || oy === "overlay") &&
          node.scrollHeight > node.clientHeight + 1;
        if (canY) return node;
      }
      node = node.parentElement;
    }
    return null;
  };

  const canNativeScroll = (target, deltaY) => {
    const box = scrollableAncestor(target);
    if (!box) return false;
    const top = box.scrollTop;
    const max = box.scrollHeight - box.clientHeight;
    if (deltaY < 0 && top > 0) return true;
    if (deltaY > 0 && top < max - 1) return true;
    return false;
  };

  window.addEventListener(
    "wheel",
    (event) => {
      if (canNativeScroll(event.target, event.deltaY)) return;
      event.preventDefault();
      if (locked) return;

      wheelAcc += event.deltaY;
      window.clearTimeout(wheelTimer);
      wheelTimer = window.setTimeout(() => {
        wheelAcc = 0;
      }, 180);

      if (Math.abs(wheelAcc) < 40) return;
      const dir = wheelAcc > 0 ? 1 : -1;
      wheelAcc = 0;
      goTo(index + dir);
    },
    { passive: false }
  );

  window.addEventListener(
    "touchstart",
    (event) => {
      if (event.touches.length !== 1) return;
      touchY = event.touches[0].clientY;
    },
    { passive: true }
  );

  window.addEventListener(
    "touchend",
    (event) => {
      if (touchY == null || locked) {
        touchY = null;
        return;
      }
      const endY = event.changedTouches[0]?.clientY;
      if (endY == null) {
        touchY = null;
        return;
      }
      const delta = touchY - endY;
      touchY = null;
      if (Math.abs(delta) < 56) return;
      if (canNativeScroll(event.target, delta)) return;
      goTo(index + (delta > 0 ? 1 : -1));
    },
    { passive: true }
  );

  document.querySelectorAll("[data-deck-to], a[href='#ecoute'], a[href='#equipe']").forEach((link) => {
    link.addEventListener("click", (event) => {
      const toAttr = link.getAttribute("data-deck-to");
      let next = toAttr != null ? Number(toAttr) : -1;
      if (next < 0) {
        const id = link.getAttribute("href")?.slice(1);
        next = panels.findIndex((p) => p.id === id);
      }
      if (next < 0) return;
      event.preventDefault();
      goTo(next);
    });
  });

  window.addEventListener("keydown", (event) => {
    if (event.defaultPrevented) return;
    const tag = (event.target instanceof HTMLElement && event.target.tagName) || "";
    if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return;
    if (event.key === "ArrowDown" || event.key === "PageDown") {
      event.preventDefault();
      goTo(index + 1);
    } else if (event.key === "ArrowUp" || event.key === "PageUp") {
      event.preventDefault();
      goTo(index - 1);
    } else if (event.key === "Home") {
      event.preventDefault();
      goTo(0);
    } else if (event.key === "End") {
      event.preventDefault();
      goTo(panels.length - 1);
    }
  });

  const bootHash = location.hash.replace("#", "");
  const boot = panels.findIndex((p) => p.id === bootHash);
  goTo(boot >= 0 ? boot : 0, true);
  document.body.dataset.deckPanel = String(index);
})();
