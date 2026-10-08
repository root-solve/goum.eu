(() => {
  const phoneNode = document.querySelector("[data-contact-phone]");
  const mailNode = document.querySelector("[data-contact-mail]");
  const youtubeNode = document.querySelector("[data-youtube]");

  const safeHttpsUrl = (value) => {
    try {
      const u = new URL(String(value || "").trim());
      if (u.protocol !== "https:") return null;
      if (u.username || u.password) return null;
      return u.href;
    } catch {
      return null;
    }
  };

  const safeMailto = (value) => {
    const mail = String(value || "").trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(mail)) return null;
    if (/[\r\n]/.test(mail)) return null;
    return mail;
  };

  const applyContact = (data) => {
    const phone = String(data.contact_phone || "").trim();
    const mail = safeMailto(data.contact_mail);
    const youtube = safeHttpsUrl(data.youtube_url);

    if (phoneNode) {
      phoneNode.textContent = phone || "—";
      const tel = phone.replace(/[^\d+]/g, "");
      if (tel && tel.length >= 6) phoneNode.setAttribute("href", `tel:${tel}`);
      else phoneNode.removeAttribute("href");
    }

    if (mailNode) {
      mailNode.textContent = mail || "—";
      if (mail) mailNode.setAttribute("href", `mailto:${encodeURIComponent(mail).replace(/%40/g, "@")}`);
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
