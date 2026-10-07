// Count Downula site. No dependencies, no storage, no network.
(() => {
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;

  // ---- time helpers (mirror the app's formatting) ----
  const parts = (ms) => {
    const t = Math.max(0, Math.floor(Math.abs(ms) / 1000));
    return { d: Math.floor(t / 86400), h: Math.floor(t / 3600) % 24, m: Math.floor(t / 60) % 60, s: t % 60 };
  };
  const pad = (n) => String(n).padStart(2, "0");
  const compact = (ms) => {
    const p = parts(ms);
    if (p.d > 0) return `${p.d}d ${p.h}h`;
    if (p.h > 0) return `${p.h}h ${pad(p.m)}m`;
    return `${pad(p.m)}:${pad(p.s)}`;
  };
  const plural = (n, w) => `${n} ${w}${n === 1 ? "" : "s"}`;
  const spoken = (ms) => {
    const p = parts(ms);
    const bits = [];
    if (p.d) bits.push(plural(p.d, "day"));
    if (p.h) bits.push(plural(p.h, "hour"));
    if (p.m) bits.push(plural(p.m, "minute"));
    bits.push(plural(p.s, "second"));
    return bits.length > 1 ? bits.slice(0, -1).join(", ") + " and " + bits.at(-1) : bits[0];
  };

  const nextHalloween = () => {
    const now = new Date();
    let t = new Date(now.getFullYear(), 9, 31, 19, 0, 0);
    if (t <= now) t = new Date(now.getFullYear() + 1, 9, 31, 19, 0, 0);
    return t;
  };

  // ---- header: the brand ring drains as you scroll the page ----
  const top = $("#top");
  const brandRing = $(".brand .ring");
  const onScroll = () => {
    const max = document.documentElement.scrollHeight - innerHeight;
    const p = max > 0 ? Math.min(1, scrollY / max) : 0;
    brandRing?.style.setProperty("--drain", (p * 0.92).toFixed(3));
    top.classList.toggle("is-scrolled", scrollY > 30);
  };
  addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  // ---- hero headline: letters drop in one by one ----
  const h1 = $("[data-split]");
  if (h1 && !reduced) {
    let i = 0;
    $$(".line", h1).forEach((line) => {
      const text = line.textContent;
      line.setAttribute("aria-hidden", "true");
      line.textContent = "";
      // keep each word unbreakable so letters never wrap mid-word
      text.split(/(\s+)/).forEach((word) => {
        if (/^\s+$/.test(word)) return line.append(word);
        const w = document.createElement("span");
        w.className = "word";
        for (const c of word) {
          const span = document.createElement("span");
          span.className = "ch";
          span.style.setProperty("--i", i++);
          span.textContent = c;
          w.append(span);
        }
        line.append(w);
      });
    });
    h1.setAttribute("aria-label", "Time, with teeth.");
  }

  // ---- hero clock: real seconds, minute ticks ----
  const ticks = $(".clock .ticks");
  if (ticks) {
    const NS = "http://www.w3.org/2000/svg";
    for (let k = 0; k < 60; k++) {
      const a = (k * 6 * Math.PI) / 180;
      const long = k % 5 === 0;
      const r1 = 455, r2 = long ? 425 : 440;
      const l = document.createElementNS(NS, "line");
      l.setAttribute("x1", 500 + r1 * Math.sin(a));
      l.setAttribute("y1", 500 - r1 * Math.cos(a));
      l.setAttribute("x2", 500 + r2 * Math.sin(a));
      l.setAttribute("y2", 500 - r2 * Math.cos(a));
      l.setAttribute("stroke-width", long ? 8 : 4);
      ticks.append(l);
    }
  }
  const hand = $(".clock .hand");
  const HAND_BASE = 47; // the drawn hand already points ~47° past twelve
  let turns = 0, lastSec = -1;
  const setHand = () => {
    if (!hand) return;
    const s = new Date().getSeconds();
    if (s < lastSec) turns++;
    lastSec = s;
    hand.style.setProperty("--rot", `${turns * 360 + s * 6 - HAND_BASE}deg`);
  };

  // ---- hero line: "Halloween is ... away" ----
  const hEl = $("[data-halloween]");
  const halloween = nextHalloween();

  // ---- tour: faux menu bar values ----
  const focusEl = $("[data-focus]");
  const sonomaEl = $("[data-sonoma]");
  const ghostEl = $("[data-ghost]");
  const clockEl = $("[data-macclock]");
  const loadedAt = Date.now();
  const focusEnd = loadedAt + (16 * 60 + 50) * 1000;
  const sonoma = loadedAt + ((15 * 24 + 23) * 3600 + 58 * 60 + 50) * 1000;

  // ---- tour: which step is in view drives the stage ----
  const stage = $(".stage");
  const steps = $$(".step");
  const newPin = $("[data-newpin]");
  const fang = $("[data-fang]");
  const setStep = (n) => {
    if (!stage || stage.dataset.step === String(n)) return;
    stage.dataset.step = n;
    steps.forEach((s) => s.classList.toggle("is-on", s.dataset.step === String(n)));
    fang?.classList.toggle("is-hot", n === 1 || n === 2);
    newPin?.classList.toggle("is-new", n < 3);
    newPin?.classList.toggle("is-hot", n === 3);
  };
  if (steps.length) {
    // the active step is whichever caption crosses a reading line; on narrow
    // screens the stage covers the top half, so that line sits lower
    const narrow = matchMedia("(max-width: 900px)");
    let queued = false;
    const pick = () => {
      queued = false;
      const y = innerHeight * (narrow.matches ? 0.75 : 0.5);
      const hit = steps.find((s) => { const r = s.getBoundingClientRect(); return r.top <= y && r.bottom > y; });
      if (hit) setStep(Number(hit.dataset.step));
      else if (steps[0].getBoundingClientRect().top > y) setStep(1);
    };
    addEventListener("scroll", () => { if (!queued) { queued = true; requestAnimationFrame(pick); } }, { passive: true });
    addEventListener("resize", pick);
    steps[0].classList.add("is-on");
    fang?.classList.add("is-hot");
    pick();
  }

  // ---- demo countdown ----
  const form = $("#demo");
  const titleIn = $("#d-title");
  const whenIn = $("#d-when");
  const card = $("#demo-card");
  const cardTitle = $("[data-card-title]");
  const cardWhen = $("[data-card-when]");
  const cardStatus = $("[data-card-status]");
  const nums = Object.fromEntries($$("[data-unit]").map((el) => [el.dataset.unit, el]));
  const toLocalInput = (d) =>
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;

  const presets = {
    halloween: () => ["Halloween", nextHalloween()],
    newyear: () => {
      const now = new Date();
      return ["New Year's Eve", new Date(now.getFullYear() + 1, 0, 1, 0, 0, 0)];
    },
    focus: () => {
      const d = new Date(Date.now() + 25 * 60 * 1000);
      d.setSeconds(0, 0);
      return ["Focus block", d];
    },
    friday: () => {
      const d = new Date();
      d.setHours(17, 0, 0, 0);
      const add = (5 - d.getDay() + 7) % 7;
      d.setDate(d.getDate() + add);
      if (d <= new Date()) d.setDate(d.getDate() + 7);
      return ["Friday at five", d];
    },
  };
  let target = nextHalloween();

  const applyPreset = (key) => {
    const [t, d] = presets[key]();
    titleIn.value = t;
    whenIn.value = toLocalInput(d);
    target = d;
    $$("[data-preset]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.preset === key)));
    renderDemo(true);
  };

  const setNum = (el, value, animate) => {
    const cur = el.lastElementChild?.textContent;
    if (cur === value) return;
    if (!animate || reduced) {
      el.innerHTML = `<span>${value}</span>`;
      return;
    }
    el.innerHTML = `<span class="out">${cur ?? ""}</span><span class="in">${value}</span>`;
  };

  const dateFmt = new Intl.DateTimeFormat(undefined, { weekday: "long", month: "long", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit" });
  const renderDemo = (animate = true) => {
    if (!card) return;
    const name = titleIn.value.trim() || "Untitled countdown";
    cardTitle.textContent = name;
    if (isNaN(target)) {
      cardWhen.textContent = "Pick a date and time";
      cardStatus.textContent = "Set a date to start counting.";
      return;
    }
    cardWhen.textContent = dateFmt.format(target);
    const ms = target - Date.now();
    const p = parts(ms);
    setNum(nums.d, String(p.d), animate);
    setNum(nums.h, String(p.h), animate);
    setNum(nums.m, String(p.m), animate);
    setNum(nums.s, String(p.s), animate);
    card.classList.toggle("is-past", ms <= 0);
    cardStatus.textContent = ms > 0 ? "Counting down." : "This one already happened. It moves to Past in the app.";
  };

  if (form) {
    form.addEventListener("submit", (e) => e.preventDefault());
    whenIn.value = toLocalInput(target);
    titleIn.addEventListener("input", () => {
      $$("[data-preset]").forEach((b) => b.setAttribute("aria-pressed", "false"));
      renderDemo(false);
    });
    whenIn.addEventListener("input", () => {
      target = new Date(whenIn.value);
      $$("[data-preset]").forEach((b) => b.setAttribute("aria-pressed", "false"));
      renderDemo(true);
    });
    $$("[data-preset]").forEach((b) => b.addEventListener("click", () => applyPreset(b.dataset.preset)));
    renderDemo(false);
  }

  // ---- one clock drives everything ----
  const macFmt = new Intl.DateTimeFormat("en-US", { weekday: "short", month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });
  const tick = () => {
    const now = Date.now();
    setHand();
    if (hEl) hEl.textContent = spoken(halloween - now);
    if (focusEl) {
      // loop the focus block so it never stalls at zero
      const left = (focusEnd - now) % (25 * 60 * 1000);
      focusEl.textContent = compact(left > 0 ? left : left + 25 * 60 * 1000);
    }
    if (sonomaEl) sonomaEl.textContent = compact(sonoma - now);
    if (ghostEl) {
      const p = parts(sonoma - now);
      ghostEl.textContent = `${p.d}d ${p.h}h ${pad(p.m)}m ${pad(p.s)}s`;
    }
    if (clockEl) clockEl.textContent = macFmt.format(now).replace(",", "").replace(",", "");
    renderDemo(true);
  };
  tick();
  // line up with the wall clock's second boundary
  setTimeout(() => { tick(); setInterval(tick, 1000); }, 1000 - (Date.now() % 1000));

  // ---- copy buttons ----
  $$("[data-copy]").forEach((btn) =>
    btn.addEventListener("click", async () => {
      const text = $(btn.dataset.copy)?.textContent ?? "";
      try {
        await navigator.clipboard.writeText(text);
        btn.textContent = "Copied";
      } catch {
        btn.textContent = "Select and copy";
      }
      setTimeout(() => (btn.textContent = "Copy"), 1800);
    })
  );

  // ---- phones and watches swing in the first time their section shows up ----
  $$(".pocket, .wrist").forEach((section) => {
    const io = new IntersectionObserver((entries) => {
      if (entries.some((e) => e.isIntersecting)) { section.classList.add("is-in"); io.disconnect(); }
    }, { threshold: 0.25 });
    io.observe(section);
  });

  $$("[data-year]").forEach((el) => (el.textContent = new Date().getFullYear()));
})();
