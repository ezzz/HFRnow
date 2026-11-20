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

  // A refused or failed avatar leaves its monogram, drawn under it by the builder.
  const dropAvatar = (img) => {
    const wrap = img.closest(".avatar-wrap");
    img.remove();
    if (wrap) { wrap.classList.remove("has-image"); }
  };

  // A refused or failed image becomes its URL as text, or a link when it is not already inside one (the app opens links).
  // Returns how to put the picture back where it was.
  const replaceWithLink = (img, src) => {
    if (img.classList.contains("avatar")) {
      const wrap = img.closest(".avatar-wrap");
      const parent = img.parentNode;
      const next = img.nextSibling;
      dropAvatar(img);
      return () => {
        if (parent && parent.isConnected) { parent.insertBefore(img, next && next.parentNode === parent ? next : null); }
        if (wrap) { wrap.classList.add("has-image"); }
      };
    }
    const insideLink = img.closest("a") !== null;
    const node = document.createElement(insideLink ? "span" : "a");
    node.className = "image-link";
    node.textContent = src;
    if (!insideLink) { node.setAttribute("href", src); }
    img.replaceWith(node);
    return () => { if (node.isConnected) { node.replaceWith(img); } };
  };

  // The pictures whose load failed, by source, with how to put each back: when a stop of the reader cut their loads, the app
  // asks for them again on return (#1187).
  const failedLoads = new Map();

  const load = (img, src) => {
    img.addEventListener("error", () => {
      const restore = replaceWithLink(img, src);
      failedLoads.set(src, (failedLoads.get(src) || []).concat([() => { restore(); img.removeAttribute("src"); load(img, src); }]));
    }, { once: true });
    // A posted picture without a description is read as "Image", not as its file name (LOT-163).
    // HFR's [img] writes the address itself as the alt, so an alt that is empty or an address counts as none.
    if (img.classList.contains("hfrplusimg")) {
      const alt = img.getAttribute("alt") || "";
      if (alt === "" || alt === src || /^https?:/i.test(alt)) { img.setAttribute("alt", "Image"); }
    }
    // The viewer's list is the original `src` of the pictures this script loaded (the attribute itself is the proxied URL).
    img.dataset.viewerSrc = src;
    img.setAttribute("src", proxied(src));
  };

  const placeholder = (img, src) => {
    if (img.classList.contains("avatar")) { dropAvatar(img); return; }
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

  // A YouTube card's thumbnail (#1037): shown only once it has loaded; refused, failed or not asked for (images on tap, no Wi-Fi,
  // a blocked host), the card stays the pill the builder wrote, with no placeholder and no link text in its place.
  const applyThumb = (img, src, decision) => {
    const card = img.closest(".video-card");
    const fail = () => { img.remove(); if (card) { card.classList.remove("has-thumb"); } };
    if (decision !== "load") { fail(); return; }
    const parent = img.parentNode;
    const next = img.nextSibling;
    img.addEventListener("load", () => { if (card) { card.classList.add("has-thumb"); } }, { once: true });
    img.addEventListener("error", () => {
      fail();
      // Put back and asked again when a stop of the reader cut it (#1187).
      failedLoads.set(src, (failedLoads.get(src) || []).concat([() => {
        if (parent && parent.isConnected) { parent.insertBefore(img, next && next.parentNode === parent ? next : null); }
        img.removeAttribute("src");
        applyThumb(img, src, "load");
      }]));
    }, { once: true });
    img.dataset.thumbSrc = src;
    img.setAttribute("src", proxied(src));
  };

  const apply = (img, src, decision) => {
    if (img.classList.contains("video-thumb")) { applyThumb(img, src, decision); return; }
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
    // The card of a plain YouTube link, or that link itself (same address, same message): the app opens it in the YouTube app or in
    // Safari (#1037). Only the message's own text link counts: not one in a quote, a spoiler or a code block (a table), nor one around a
    // picture (that tap is the picture's). The app checks the address again; nothing else of the page is sent.
    const anchor = target.closest("a[href]");
    if (anchor) {
      const article = anchor.closest("article");
      const href = anchor.getAttribute("href");
      const isCard = anchor.classList.contains("video-card");
      const isCardLink = anchor.matches(".content a.cLink") && !anchor.closest("table") && anchor.querySelector("img") === null
        && article !== null && Array.from(article.querySelectorAll("a.video-card")).some((card) => card.getAttribute("href") === href);
      if (isCard || isCardLink) {
        event.preventDefault();
        channel.postMessage({ type: "videolink", token, url: href });
        return;
      }
    }
    // A loaded posted picture opens the viewer (LOT-109). Smileys and avatars have no `hfrplusimg` class; a picture that is
    // still a placeholder or became a link is no longer an `img`, so it is not in the list the app receives.
    const picture = target.closest("img.hfrplusimg");
    if (picture && picture.closest(".content, .signature")) {
      // A picture inside a closed spoiler is loaded but hidden: a swipe must not show it.
      const pictures = Array.from(document.querySelectorAll(".content img.hfrplusimg[data-viewer-src], .signature img.hfrplusimg[data-viewer-src]"))
        .filter((img) => !img.closest("table.spoiler:not(.open)"));
      const index = pictures.indexOf(picture);
      if (index >= 0) {
        event.preventDefault();
        // The link around the picture goes along (#912): `href` is the resolved address, or null outside a link. The page never
        // navigates; the app decides between the viewer, the forum and a confirmation.
        const anchor = picture.closest("a[href]");
        channel.postMessage({ type: "image", token, urls: pictures.map((img) => img.dataset.viewerSrc), index, link: anchor ? anchor.href : null });
        return;
      }
    }
    const menu = target.closest("button[data-menu]");
    if (menu) {
      event.preventDefault();
      // Only numbers and one of two names leave the page: the app decodes them and ignores anything else. The rectangle
      // (viewport coordinates) is where the app anchors the menu, as legacy's edit menu at the tapped point (issue #594).
      // After a pinch zoom `getBoundingClientRect` is in layout (CSS) coordinates: the visual viewport's offset and scale
      // bring it to what the user sees (both are 0 and 1 without zoom).
      const box = menu.getBoundingClientRect();
      const vv = window.visualViewport;
      const scale = vv && vv.scale > 0 ? vv.scale : 1;
      const offsetX = vv ? vv.offsetLeft : 0;
      const offsetY = vv ? vv.offsetTop : 0;
      channel.postMessage({
        type: "menu", token, post: Number(menu.dataset.post), source: menu.dataset.menu,
        x: (box.x - offsetX) * scale, y: (box.y - offsetY) * scale, width: box.width * scale, height: box.height * scale
      });
      return;
    }
    const blocked = target.closest("table.quote-blocked");
    if (blocked) {
      // Collapsed: any tap opens it, even on the header link. Open: only its own header (not a nested quote's, not its body) closes it, and its link still works.
      const onHeader = target.closest("b.s1")?.closest("table") === blocked;
      if (!blocked.classList.contains("open") || (onHeader && !target.closest("a"))) {
        event.preventDefault();
        blocked.classList.toggle("open");
        syncDisclosure(blocked);
        return;
      }
    }
    const spoiler = target.closest("table.spoiler");
    if (spoiler && !target.closest("a")) { spoiler.classList.toggle("open"); syncDisclosure(spoiler); }
  });

  // Accessibility (LOT-163). HFR draws quotes, code and spoilers as tables: VoiceOver would read "tableau, 1 ligne, 1 colonne".
  // Only attributes are set here, from what the page already holds; nothing is read back by the app.
  const headerOf = (table) => Array.from(table.querySelectorAll("b.s1, b.s1Topic")).find((b) => b.closest("table") === table) || null;
  // A spoiler's header, and a collapsed blocklisted quote's, is the button that opens it (its tap is a click, which VoiceOver's
  // double tap sends too). An opened blocklisted quote's header holds a link again, so it is no button (a button's children are
  // presentational). The pseudo a blocklisted quote hides on screen is never named here.
  function syncDisclosure(table) {
    const head = headerOf(table);
    if (!head) { return; }
    const open = table.classList.contains("open");
    if (table.classList.contains("spoiler") || !open) {
      head.setAttribute("role", "button");
      head.setAttribute("tabindex", "0");
      head.setAttribute("aria-expanded", open ? "true" : "false");
    } else {
      ["role", "tabindex", "aria-expanded"].forEach((name) => head.removeAttribute(name));
    }
    if (table.classList.contains("quote-hide-author") && !open) { head.setAttribute("aria-label", "Citation masquée"); }
    else { head.removeAttribute("aria-label"); }
    table.setAttribute("aria-label", groupName(table));
  }
  function groupName(table) {
    if (table.classList.contains("spoiler")) { return "Spoiler"; }
    if (table.classList.contains("code")) { return "Code"; }
    if (table.classList.contains("fixed")) { return "Texte préformaté"; }
    if (table.classList.contains("quote-hide-author") && !table.classList.contains("open")) { return "Citation masquée"; }
    const head = headerOf(table);
    const text = head ? head.textContent.replace(/\s+/g, " ").trim() : "";
    return text !== "" ? text : "Citation";
  }
  document.querySelectorAll("table.citation, table.oldcitation, table.quote, table.code, table.fixed, table.spoiler").forEach((table) => {
    table.setAttribute("role", "group");
    table.setAttribute("aria-label", groupName(table));
    if (table.matches(".spoiler, .quote-blocked")) { syncDisclosure(table); }
  });
  document.addEventListener("keydown", (event) => {
    const target = event.target instanceof Element ? event.target : null;
    if ((event.key === "Enter" || event.key === " ") && target && target.matches("[role=button][tabindex]") && target.closest("table")) {
      event.preventDefault();
      target.click();
    }
  });

  // Landing on a message (LOT-111): images that load after the first scroll push the message down, so the document keeps
  // it at the top until the user touches the page or every image has settled. WebKit has no scroll anchoring.
  let pinned = null;
  // `scrollY` right after the pin's own scroll: a scroll that moves away from it came from the user, including the ones that
  // send no touch, wheel or key event (VoiceOver, status-bar tap).
  let pinY = 0;
  let scheduleReport = () => {};
  const pinNow = () => { pinned.scrollIntoView({ block: "start" }); pinY = window.scrollY; };
  const releasePin = () => {
    if (pinned === null) { return; }
    pinned = null;
    scheduleReport(); // the landing may have produced no scroll event to report from
  };
  const settled = () => Array.from(document.images).every((img) => img.complete);
  let settleTimer = null;
  const repin = () => {
    if (pinned === null) { return; }
    pinNow();
    // A failed image becomes a link of another height after this handler (see `load` above): release only after one more
    // turn of the event loop, with a last scroll.
    clearTimeout(settleTimer);
    if (settled()) {
      settleTimer = setTimeout(() => {
        if (pinned !== null && settled()) { pinNow(); releasePin(); }
      }, 0);
    }
  };
  ["touchstart", "wheel", "keydown", "mousedown"].forEach((name) =>
    window.addEventListener(name, releasePin, { passive: true, capture: true }));

  // WebKit resets a new document's scroll view to its top when it applies the document's first layer-tree commit, which
  // drops a scroll made in that same commit: a landing or a refresh's restore opened at the top now and then (issue #642).
  // A scroll the app asks for waits two animation frames, which puts it in a later commit. It runs once: a second scroll
  // would undo a user's scroll that sends no event (VoiceOver, status-bar tap). Nothing native waits on the frames, which do
  // not come while the page is hidden.
  const afterFirstFrames = (scroll) => requestAnimationFrame(() => requestAnimationFrame(scroll));
  // WebKit's reset of a new document reaches the scroll view and the page at different times (#995): the scroll view at its
  // top while the page still holds the previous document's offset, or the page's own position pushed back after the scroll
  // view's reset. A reset still on its way to the page undid a restore made before it (`scrollY` 1000, then 0). So a scroll the
  // app asks for also waits until the page shows what the scroll view showed when it was asked (`from`, its reading top in CSS
  // pixels), for at most `agreementFrames` frames, after which it scrolls anyway. The member touching the page meanwhile
  // (`touchstart`, `wheel`, `keydown`, `mousedown`) cancels it: the page is theirs, as for the landing's pin. A scroll that
  // sends no event (VoiceOver, a status-bar tap) during the wait cannot be told from the reset by the page: the app's scroll
  // still runs after it, as it did after the two frames before #995, now up to half a second later.
  const agreementFrames = 30;
  // Counted, not timed: WebKit coarsens `performance.now()` to a millisecond, which a touch and an ask can share.
  let touches = 0;
  ["touchstart", "wheel", "keydown", "mousedown"].forEach((name) =>
    window.addEventListener(name, () => { touches += 1; }, { passive: true, capture: true }));
  const afterAgreement = (from, scroll) => {
    const touchesWhenAsked = touches;
    let frames = 0;
    const step = () => {
      if (touches !== touchesWhenAsked) { return; }
      if (typeof from !== "number" || Math.abs(window.scrollY - from) <= 1 || frames >= agreementFrames) {
        scroll();
        return;
      }
      frames += 1;
      requestAnimationFrame(step);
    };
    afterFirstFrames(step);
  };
  document.addEventListener("load", repin, true);
  document.addEventListener("error", repin, true);
  new ResizeObserver(repin).observe(document.documentElement);

  window.hfrReader = {
    // The pictures of `sources` whose loads a stop of the reader cut (#1187): a failed one is put back where it was and
    // asked again, one whose load never ended is asked again. Nothing else is fetched and the page does not move.
    retryImages: (sources) => {
      const wanted = new Set(sources);
      // First the loads that never ended, then the failed ones put back (which start their own load).
      // A cut load may end as `complete` with no picture and no `error`: only a picture that has its pixels is left alone.
      document.querySelectorAll("img[data-viewer-src], img[data-thumb-src]").forEach((img) => {
        const src = img.dataset.viewerSrc || img.dataset.thumbSrc;
        if ((img.complete && img.naturalWidth > 0) || !wanted.has(src)) { return; }
        const current = img.getAttribute("src");
        img.removeAttribute("src");
        img.setAttribute("src", current);
      });
      for (const src of wanted) {
        const retries = failedLoads.get(src) || [];
        failedLoads.delete(src);
        retries.forEach((retry) => retry());
      }
      return true;
    },
    scrollToPost: (number) => {
      releasePin();
      const element = document.getElementById("t" + number);
      if (element) { afterFirstFrames(() => element.scrollIntoView({ block: "start" })); }
      return element !== null;
    },
    // A refresh's restore (LOT-186): `scrollY` counts from the bars' edge, so `y` is the reading top. `from` is the scroll
    // view's reading top when it was asked (`afterAgreement`).
    restoreScroll: (y, from) => {
      afterAgreement(from, () => window.scrollTo(0, y));
      return true;
    },
    // "Citer extrait" / "Citer gras" (LOT-086): reports the selection and the message it sits in. Only a selection that starts
    // and ends inside the same message is reported: quoting message A with the words of message B would misattribute them.
    quoteSelection: (bold) => {
      const selection = window.getSelection();
      if (!selection || selection.rangeCount === 0 || selection.isCollapsed) { return false; }
      const text = selection.toString();
      if (text.trim().length === 0) { return false; }
      const messageOf = (node) => {
        const element = node instanceof Element ? node : (node ? node.parentElement : null);
        return element ? element.closest("article[data-post]:not(.continuation)") : null;
      };
      const article = messageOf(selection.anchorNode);
      if (article === null || article !== messageOf(selection.focusNode)) { return false; }
      channel.postMessage({ type: "quote", token, post: Number(article.dataset.post), text: Array.from(text).slice(0, 20000).join(""), bold: bold === true });
      return true;
    },
    // Scrolls to the message and keeps it there while the page settles. `from` as for `restoreScroll`.
    landOnPost: (number, from) => {
      const element = document.getElementById("t" + number);
      if (element) {
        afterAgreement(from, () => {
          element.scrollIntoView({ block: "start" });
          if (settled()) { pinned = null; scheduleReport(); } else { pinned = element; pinY = window.scrollY; }
        });
      }
      return element !== null;
    }
  };

  // The topmost message on screen, reported when scrolling pauses (the app records it as the reading position).
  const topPost = () => {
    const posts = document.querySelectorAll("article[data-post]:not(.continuation)");
    for (const post of posts) {
      const box = post.getBoundingClientRect();
      if (box.bottom <= 1) { continue; }
      // The first message below the top edge counts only when it is on screen: one entirely below the viewport is unread.
      return box.top < window.innerHeight ? Number(post.dataset.post) : null;
    }
    return null;
  };
  let reported = null;
  let timer = null;
  scheduleReport = () => {
    clearTimeout(timer);
    timer = setTimeout(() => {
      const post = topPost();
      if (post !== null && post !== reported) {
        reported = post;
        channel.postMessage({ type: "position", token, post });
      }
    }, 500);
  };
  // The page's end on screen (legacy `notifyScrollState`, MessagesView.swift:1013-1035 @ 87fe0d1c: `scrollY + innerHeight`
  // within 2 points of the bottom), reported on a change only: the app shows the end-of-page bar (#820). Only a pinch zoom
  // reads the visual viewport: on iOS its `pageTop` comes back from the UI process later than `scrollY`, so a scroll event
  // read it stale and the way back to the top went unreported (#924, CI job 133081541823).
  let atEnd = null;
  const reportEdge = () => {
    const vv = window.visualViewport;
    const zoomed = vv !== null && vv !== undefined && vv.scale > 1.01;
    const bottom = zoomed ? vv.pageTop + vv.height : window.scrollY + window.innerHeight;
    const height = Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0);
    const now = height - bottom <= 2;
    if (now !== atEnd) {
      atEnd = now;
      channel.postMessage({ type: "edge", token, bottom: now });
    }
  };
  new ResizeObserver(reportEdge).observe(document.documentElement);
  if (window.visualViewport) {
    window.visualViewport.addEventListener("resize", reportEdge, { passive: true });
    window.visualViewport.addEventListener("scroll", reportEdge, { passive: true });
  }

  window.addEventListener("scroll", () => {
    if (pinned !== null && Math.abs(window.scrollY - pinY) > 4) { releasePin(); }
    if (pinned === null) { scheduleReport(); }
    reportEdge();
  }, { passive: true });

  const images = Array.from(document.querySelectorAll("img[src]"));
  const sources = images.map((img) => img.getAttribute("src"));
  channel.postMessage({ type: "images", token, urls: sources })
    .then((decisions) => images.forEach((img, index) => apply(img, sources[index], decisions[index])))
    .catch(() => images.forEach((img, index) => apply(img, sources[index], "block")))
    .finally(() => { channel.postMessage({ type: "ready", token }); reportEdge(); });
})();
