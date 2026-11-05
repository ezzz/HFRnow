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
    // The viewer's list is the original `src` of the pictures this script loaded (the attribute itself is the proxied URL).
    img.dataset.viewerSrc = src;
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
    // A loaded posted picture opens the viewer (LOT-109). Smileys and avatars have no `hfrplusimg` class; a picture that is
    // still a placeholder or became a link is no longer an `img`, so it is not in the list the app receives.
    const picture = target.closest("img.hfrplusimg");
    if (picture && picture.closest(".content, .signature")) {
      const pictures = Array.from(document.querySelectorAll(".content img.hfrplusimg[data-viewer-src], .signature img.hfrplusimg[data-viewer-src]"));
      const index = pictures.indexOf(picture);
      if (index >= 0) {
        event.preventDefault();
        channel.postMessage({ type: "image", token, urls: pictures.map((img) => img.dataset.viewerSrc), index });
        return;
      }
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

  window.hfrReader = {
    scrollToPost: (number) => {
      const element = document.getElementById("t" + number);
      if (element) { element.scrollIntoView({ block: "start" }); }
      return element !== null;
    }
  };

  const images = Array.from(document.querySelectorAll("img[src]"));
  const sources = images.map((img) => img.getAttribute("src"));
  channel.postMessage({ type: "images", token, urls: sources })
    .then((decisions) => images.forEach((img, index) => apply(img, sources[index], decisions[index])))
    .catch(() => images.forEach((img, index) => apply(img, sources[index], "block")))
    .finally(() => channel.postMessage({ type: "ready", token }));
})();
