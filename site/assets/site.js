// Reel site — 60 lines of vanilla JS. No frameworks, no analytics, no fonts.
(() => {
  "use strict";

  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

  /* ---------------------------------------------------------- sticky nav */
  const nav = $(".nav");
  if (nav) {
    const onScroll = () => nav.classList.toggle("is-stuck", window.scrollY > 6);
    onScroll();
    addEventListener("scroll", onScroll, { passive: true });
  }

  /* ------------------------------------------------------------ copy buttons */
  for (const btn of $$("[data-copy]")) {
    const hint = $(".copy-hint", btn);
    const original = hint ? hint.textContent : "";
    btn.addEventListener("click", async () => {
      const text = btn.getAttribute("data-copy") || "";
      try {
        await navigator.clipboard.writeText(text);
      } catch {
        const area = document.createElement("textarea");
        area.value = text;
        area.setAttribute("readonly", "");
        area.style.position = "fixed";
        area.style.opacity = "0";
        document.body.append(area);
        area.select();
        document.execCommand("copy");
        area.remove();
      }
      if (!hint) return;
      hint.textContent = "Copied";
      btn.dataset.copied = "true";
      setTimeout(() => {
        hint.textContent = original;
        delete btn.dataset.copied;
      }, 1400);
    });
  }

  /* ------------------------------------------------------------------ tabs */
  for (const list of $$('[role="tablist"]')) {
    const tabs = $$('[role="tab"]', list);
    const panelFor = (tab) => document.getElementById(tab.getAttribute("aria-controls"));
    const select = (tab) => {
      for (const t of tabs) {
        const on = t === tab;
        t.setAttribute("aria-selected", String(on));
        t.tabIndex = on ? 0 : -1;
        const panel = panelFor(t);
        if (panel) panel.hidden = !on;
      }
    };
    tabs.forEach((tab, i) => {
      tab.tabIndex = tab.getAttribute("aria-selected") === "true" ? 0 : -1;
      tab.addEventListener("click", () => select(tab));
      tab.addEventListener("keydown", (e) => {
        const dir = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
        if (!dir) return;
        e.preventDefault();
        const next = tabs[(i + dir + tabs.length) % tabs.length];
        next.focus();
        select(next);
      });
    });
  }

  /* -------------------------------------------------- latest release stamp */
  const setAll = (name, value) => {
    for (const el of $$(`[data-${name}]`)) el.textContent = value;
  };

  const sizeLabel = (bytes) => {
    if (!bytes) return null;
    const mb = bytes / 1_000_000;
    return `${mb >= 10 ? Math.round(mb) : mb.toFixed(1)} MB`;
  };

  (async () => {
    if (!$("[data-version]")) return;
    let release = null;
    try {
      const cached = sessionStorage.getItem("reel:release");
      const fresh = cached && Date.now() - JSON.parse(cached).at < 3_600_000;
      release = fresh ? JSON.parse(cached).data : null;
      if (!release) {
        const res = await fetch("https://api.github.com/repos/waylake/reel/releases/latest", {
          headers: { Accept: "application/vnd.github+json" },
        });
        if (res.ok) {
          release = await res.json();
          sessionStorage.setItem("reel:release", JSON.stringify({ at: Date.now(), data: release }));
        }
      }
    } catch {
      return; // static values in the markup stay
    }
    if (!release || !release.tag_name) return;

    setAll("version", release.tag_name.replace(/^v/, ""));
    const asset = (release.assets || []).find((a) => a.name === "Reel.app.zip") || (release.assets || [])[0];
    const size = sizeLabel(asset && asset.size);
    if (size) setAll("size", size);
  })();
})();
