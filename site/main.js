(() => {
  const root = document.documentElement;
  root.classList.remove("no-js");
  root.classList.add("js");

  const $ = (selector, scope = document) => scope.querySelector(selector);
  const $$ = (selector, scope = document) => [...scope.querySelectorAll(selector)];
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const live = $("#live-region");
  const announce = (message) => {
    if (!live) return;
    live.textContent = "";
    window.setTimeout(() => { live.textContent = message; }, 20);
  };

  // Sticky header state, driven by a sentinel rather than a scroll listener.
  const header = $("#site-header");
  const sentinel = $(".scroll-sentinel");
  if (header && sentinel) {
    new IntersectionObserver(([entry]) => header.classList.toggle("scrolled", !entry.isIntersecting))
      .observe(sentinel);
  }

  // Mobile menu.
  const menuButton = $("#menu-button");
  const menu = $("#mobile-menu");
  if (menuButton && menu) {
    const controls = $$("a, button", menu);
    let open = false;
    const setMenu = (next, returnFocus = false) => {
      open = next;
      menuButton.setAttribute("aria-expanded", String(next));
      menu.hidden = !next;
      if (next) {
        const first = controls[0];
        if (first) first.focus();
      } else if (returnFocus) {
        menuButton.focus();
      }
    };
    menuButton.addEventListener("click", () => setMenu(!open));
    menu.addEventListener("click", (event) => { if (event.target.closest("a")) setMenu(false); });
    menu.addEventListener("keydown", (event) => {
      if (event.key === "Escape") { event.preventDefault(); setMenu(false, true); return; }
      if (event.key !== "Tab" || controls.length === 0) return;
      const first = controls[0];
      const last = controls[controls.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    });
    document.addEventListener("pointerdown", (event) => {
      if (open && !menu.contains(event.target) && !menuButton.contains(event.target)) setMenu(false);
    });
    window.matchMedia("(min-width: 1041px)").addEventListener("change", (event) => {
      if (event.matches && open) setMenu(false);
    });
  }

  // Screenshot gallery tabs.
  const tabs = $$(".gallery-tab");
  if (tabs.length) {
    const select = (tab) => {
      tabs.forEach((candidate) => {
        const selected = candidate === tab;
        candidate.classList.toggle("is-active", selected);
        candidate.setAttribute("aria-selected", String(selected));
        candidate.tabIndex = selected ? 0 : -1;
        const panel = document.getElementById(candidate.getAttribute("aria-controls"));
        if (panel) {
          panel.classList.toggle("is-active", selected);
          panel.hidden = !selected;
        }
      });
      tab.focus();
    };
    tabs.forEach((tab) => {
      const panel = document.getElementById(tab.getAttribute("aria-controls"));
      if (panel) panel.hidden = tab.getAttribute("aria-selected") !== "true";
      tab.addEventListener("click", () => select(tab));
    });
    const tablist = $(".gallery-tabs");
    tablist.addEventListener("keydown", (event) => {
      const current = tabs.indexOf(document.activeElement);
      if (current < 0) return;
      let next = current;
      if (event.key === "ArrowRight") next = (current + 1) % tabs.length;
      else if (event.key === "ArrowLeft") next = (current - 1 + tabs.length) % tabs.length;
      else if (event.key === "Home") next = 0;
      else if (event.key === "End") next = tabs.length - 1;
      else return;
      event.preventDefault();
      select(tabs[next]);
    });
  }

  // Copy buttons.
  document.addEventListener("click", async (event) => {
    const button = event.target.closest("[data-copy]");
    if (!button) return;
    const source = document.getElementById(button.dataset.copy);
    if (!source) return;
    const text = source.innerText.trim();
    let copied = false;
    try {
      await navigator.clipboard.writeText(text);
      copied = true;
    } catch {
      const selection = window.getSelection();
      const range = document.createRange();
      range.selectNodeContents(source);
      selection.removeAllRanges();
      selection.addRange(range);
    }
    const original = button.textContent;
    button.textContent = copied ? "Copied" : "Selected";
    button.classList.toggle("is-copied", copied);
    announce(copied ? "Copied to clipboard" : "Command selected. Press copy.");
    window.setTimeout(() => {
      button.textContent = original;
      button.classList.remove("is-copied");
    }, 1600);
  });

  // Entrance motion only when it is welcome.
  const reveals = $$(".reveal");
  if ("IntersectionObserver" in window && !reduceMotion.matches) {
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("in");
        observer.unobserve(entry.target);
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
    reveals.forEach((element) => observer.observe(element));
  } else {
    reveals.forEach((element) => element.classList.add("in"));
  }
})();
