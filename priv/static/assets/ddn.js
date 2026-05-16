(() => {
  // Clock in top bar
  function tick() {
    const d = new Date();
    const t = d.toTimeString().slice(0, 5);
    const el = document.getElementById("clk");
    if (el) el.textContent = t;
  }
  tick();
  setInterval(tick, 1000 * 30);

  // Copy ssh command + toast
  function showToast(msg) {
    const t = document.getElementById("toast");
    if (!t) return;
    t.textContent = msg;
    t.classList.add("show");
    setTimeout(() => t.classList.remove("show"), 1400);
  }

  async function copySsh() {
    const cmd = "ssh bbs.foglet.io";
    try {
      await navigator.clipboard.writeText(cmd);
      showToast("copied: " + cmd);
    } catch (e) {
      const ta = document.createElement("textarea");
      ta.value = cmd;
      document.body.appendChild(ta);
      ta.select();
      document.execCommand("copy");
      ta.remove();
      showToast("copied: " + cmd);
    }
  }

  function bind(id) {
    const el = document.getElementById(id);
    if (el) el.addEventListener("click", copySsh);
  }
  bind("copy-btn");
  bind("copy-btn-2");
  bind("ssh-cta");
  bind("ssh-cta-2");

  // keyboard hotkey: C to copy, G to "goodbye" (scroll to top)
  window.addEventListener("keydown", (e) => {
    if (e.target && (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA")) return;
    if (e.key === "c" || e.key === "C") copySsh();
    if (e.key === "g" || e.key === "G") window.scrollTo({ top: 0 });
  });
})();
