(() => {
  const phoneNode = document.querySelector("[data-contact-phone]");
  const mailNode = document.querySelector("[data-contact-mail]");
  const youtubeNode = document.querySelector("[data-youtube]");

  const applyContact = (data) => {
    const phone = (data.contact_phone || "").trim();
    const mail = (data.contact_mail || "").trim();
    const youtube = (data.youtube_url || "").trim();

    if (phoneNode) {
      phoneNode.textContent = phone || "—";
      const tel = phone.replace(/[^\d+]/g, "");
      if (tel) phoneNode.setAttribute("href", `tel:${tel}`);
      else phoneNode.removeAttribute("href");
    }

    if (mailNode) {
      mailNode.textContent = mail || "—";
      if (mail) mailNode.setAttribute("href", `mailto:${mail}`);
      else mailNode.removeAttribute("href");
    }

    if (youtubeNode) {
      if (youtube) {
        youtubeNode.href = youtube;
        youtubeNode.hidden = false;
      } else {
        youtubeNode.removeAttribute("href");
        youtubeNode.hidden = true;
      }
    }

    const ld = document.querySelector('script[type="application/ld+json"]');
    if (!ld) return;
    try {
      const graph = JSON.parse(ld.textContent);
      const nodes = graph["@graph"] || [graph];
      const band = nodes.find((n) => n["@type"] === "MusicGroup");
      if (!band) return;
      if (mail) band.email = mail;
      if (phone) band.telephone = phone;
      if (youtube) {
        band.sameAs = Array.isArray(band.sameAs)
          ? [...new Set([...band.sameAs, youtube])]
          : [youtube];
      }
      ld.textContent = JSON.stringify(graph);
    } catch (_) {
      /* ignore */
    }
  };

  fetch("/api/site", { cache: "no-store" })
    .then((res) => {
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return res.json();
    })
    .then(applyContact)
    .catch((err) => {
      console.error(err);
    });
})();
