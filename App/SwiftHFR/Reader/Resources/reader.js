// SwiftHFR topic reader (LOT-083). Injected by the app as a user script in its own content world: the page itself runs no
// script (content JavaScript is off and the CSP says script-src 'none'). This file only adapts the DOM; every decision
// (which image loads, which link opens, which video plays) is taken by the app.
(() => {
  "use strict";
  const channel = window.webkit.messageHandlers.reader;
  const token = Number(document.documentElement.dataset.token);
  const proxied = (src) => "hfrreader://image/?u=" + encodeURIComponent(src);

  const hostOf = (src) => {
    try { return new URL(src).host; } catch (error) { return ""; }
  };

  // A refused or failed image becomes its URL as text, or a link when it is not already inside one (the app opens links).
  const replaceWithLink = (img, src) => {
    if (img.classList.contains("avatar")) { img.remove(); return; }
    const insideLink = img.closest("a") !== null;
    const node = document.createElement(insideLink ? "span" : "a");
    node.className = "image-link";
    node.textContent = src;
    if (!insideLink) { node.setAttribute("href", src); }
    img.replaceWith(node);
  };

  const load = (img, src) => {
    img.addEventListener("error", () => replaceWithLink(img, src), { once: true });
    img.setAttribute("src", proxied(src));
  };

  const placeholder = (img, src) => {
    if (img.classList.contains("avatar")) { img.remove(); return; }
    const button = document.createElement("button");
    button.type = "button";
    button.className = "image-tap";
    const host = hostOf(src);
    button.textContent = host ? "Image (" + host + ") · toucher pour charger" : "Image · toucher pour charger";
    button.setAttribute("aria-label", host ? "Charger l'image de " + host : "Charger l'image");
    button.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      // Consent is recorded by the app for this exact URL before the image is asked for.
      channel.postMessage({ type: "tap", token, url: src }).then((allowed) => {
        if (allowed === true) { button.replaceWith(img); load(img, src); }
      });
    });
    img.replaceWith(button);
  };

  const apply = (img, src, decision) => {
    if (decision === "load") { load(img, src); }
    else if (decision === "tap") { placeholder(img, src); }
    else { replaceWithLink(img, src); }
  };

  document.addEventListener("click", (event) => {
    const target = event.target instanceof Element ? event.target : null;
    if (!target) { return; }
    const video = target.closest("button.video");
    if (video) {
      event.preventDefault();
      channel.postMessage({ type: "video", token, post: Number(video.dataset.post), index: Number(video.dataset.video) });
      return;
    }
    const menu = target.closest("button[data-menu]");
    if (menu) {
      event.preventDefault();
      // Only a number and one of two names leave the page: the app decodes them and ignores anything else.
      channel.postMessage({ type: "menu", token, post: Number(menu.dataset.post), source: menu.dataset.menu });
      return;
    }
    const spoiler = target.closest("table.spoiler");
    if (spoiler && !target.closest("a")) { spoiler.classList.toggle("open"); }
  });

  // Landing on a message (LOT-111): images that load after the first scroll push the message down, so the document keeps
  // it at the top until the user touches the page or every image has settled. WebKit has no scroll anchoring.
  let pinned = null;
  const releasePin = () => { pinned = null; };
  const settled = () => Array.from(document.images).every((img) => img.complete);
  let settleTimer = null;
  const repin = () => {
    if (pinned === null) { return; }
    pinned.scrollIntoView({ block: "start" });
    // A failed image becomes a link of another height after this handler (see `load` above): release only after one more
    // turn of the event loop, with a last scroll.
    clearTimeout(settleTimer);
    if (settled()) {
      settleTimer = setTimeout(() => {
        if (pinned !== null && settled()) { pinned.scrollIntoView({ block: "start" }); releasePin(); }
      }, 0);
    }
  };
  ["touchstart", "wheel", "keydown", "mousedown"].forEach((name) =>
    window.addEventListener(name, releasePin, { passive: true, capture: true }));
  document.addEventListener("load", repin, true);
  document.addEventListener("error", repin, true);
  new ResizeObserver(repin).observe(document.documentElement);

  window.hfrReader = {
    scrollToPost: (number) => {
      releasePin();
      const element = document.getElementById("t" + number);
      if (element) { element.scrollIntoView({ block: "start" }); }
      return element !== null;
    },
    // Scrolls to the message and keeps it there while the page settles.
    landOnPost: (number) => {
      const element = document.getElementById("t" + number);
      if (element) { element.scrollIntoView({ block: "start" }); pinned = settled() ? null : element; }
      return element !== null;
    }
  };

  // The topmost message on screen, reported when scrolling pauses (the app records it as the reading position).
  const topPost = () => {
    const posts = document.querySelectorAll("article[data-post]:not(.continuation)");
    let top = null;
    for (const post of posts) {
      if (post.getBoundingClientRect().bottom > 1) { top = post; break; }
    }
    return top === null ? null : Number(top.dataset.post);
  };
  let reported = null;
  let timer = null;
  window.addEventListener("scroll", () => {
    if (pinned !== null) { return; }
    clearTimeout(timer);
    timer = setTimeout(() => {
      const post = topPost();
      if (post !== null && post !== reported) {
        reported = post;
        channel.postMessage({ type: "position", token, post });
      }
    }, 500);
  }, { passive: true });

  const images = Array.from(document.querySelectorAll("img[src]"));
  const sources = images.map((img) => img.getAttribute("src"));
  channel.postMessage({ type: "images", token, urls: sources })
    .then((decisions) => images.forEach((img, index) => apply(img, sources[index], decisions[index])))
    .catch(() => images.forEach((img, index) => apply(img, sources[index], "block")))
    .finally(() => channel.postMessage({ type: "ready", token }));
})();
