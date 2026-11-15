(function () {
  const menu = document.querySelector('[data-menu]');
  const toggle = document.querySelector('[data-menu-toggle]');
  if (menu && toggle) {
    function setOpen(open) {
      menu.classList.toggle('is-open', open);
      toggle.setAttribute('aria-expanded', String(open));
      toggle.setAttribute('aria-label', open ? 'Закрыть меню' : 'Открыть меню');
      document.body.classList.toggle('menu-open', open);
    }
    toggle.addEventListener('click', () => setOpen(!menu.classList.contains('is-open')));
    document.addEventListener('keydown', e => { if (e.key === 'Escape') setOpen(false); });
    menu.querySelectorAll('a').forEach(a => a.addEventListener('click', () => setOpen(false)));
  }
  document.querySelectorAll('[data-year]').forEach(el => el.textContent = new Date().getFullYear());
  const c = window.FORMA_CONFIG || {};
  const email = typeof c.contactEmail === 'string' ? c.contactEmail.trim() : '';
  const validEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) && !email.endsWith('.example');
  document.querySelectorAll('[data-contact-link]').forEach(el => {
    if (validEmail) {
      el.href = 'mailto:' + email;
      el.textContent = email;
      el.removeAttribute('aria-disabled');
    } else {
      el.hidden = true;
    }
  });
  document.querySelectorAll('[data-contact-unset]').forEach(el => { el.hidden = validEmail; });
  const portfolio = typeof c.portfolioUrl === 'string' ? c.portfolioUrl.trim() : '';
  document.querySelectorAll('[data-portfolio-link]').forEach(el => {
    if (/^https:\/\//i.test(portfolio)) { el.href=portfolio; el.hidden=false; } else { el.hidden=true; }
  });
  if ('IntersectionObserver' in window && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
    const observer = new IntersectionObserver(entries => {
      entries.forEach(entry => { if (entry.isIntersecting) { entry.target.classList.add('visible'); observer.unobserve(entry.target); } });
    }, { threshold: 0.08 });
    document.querySelectorAll('.reveal').forEach(el => observer.observe(el));
  } else { document.querySelectorAll('.reveal').forEach(el => el.classList.add('visible')); }
})();
