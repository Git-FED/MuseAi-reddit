(function () {
  'use strict';

  const STORAGE_KEY = 'museai-theme';

  function readTheme() {
    try {
      return localStorage.getItem(STORAGE_KEY) === 'dark' ? 'dark' : 'light';
    } catch (_) {
      return 'light';
    }
  }

  function updateControls(theme) {
    document.querySelectorAll('[data-theme-toggle], #themeToggle').forEach((button) => {
      const dark = theme === 'dark';
      button.textContent = dark ? '☀️' : '🌙';
      button.setAttribute('aria-label', dark ? 'Switch to light mode' : 'Switch to dark mode');
      button.setAttribute('title', dark ? 'Switch to light mode' : 'Switch to dark mode');
      button.setAttribute('aria-pressed', String(dark));
    });
  }

  function applyTheme(theme, persist) {
    const normalized = theme === 'dark' ? 'dark' : 'light';
    document.documentElement.classList.toggle('theme-dark', normalized === 'dark');
    if (document.body) document.body.classList.toggle('dark', normalized === 'dark');
    if (persist) {
      try { localStorage.setItem(STORAGE_KEY, normalized); } catch (_) {}
    }
    updateControls(normalized);
    return normalized;
  }

  // Apply before page paint where possible, preventing a light-mode flash.
  applyTheme(readTheme(), false);

  window.museAiTheme = {
    get current() {
      return document.documentElement.classList.contains('theme-dark') ? 'dark' : 'light';
    },
    apply(theme) {
      return applyTheme(theme, true);
    },
    toggle() {
      return applyTheme(this.current === 'dark' ? 'light' : 'dark', true);
    }
  };

  function bind() {
    applyTheme(readTheme(), false);
    document.querySelectorAll('[data-theme-toggle], #themeToggle').forEach((button) => {
      if (button.dataset.themeBound) return;
      button.dataset.themeBound = 'true';
      button.addEventListener('click', () => window.museAiTheme.toggle());
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bind, { once: true });
  } else {
    bind();
  }
})();
