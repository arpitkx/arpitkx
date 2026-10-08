/**
 * CYBERTYPER - Shared Header Navigation & Dropdown Controller (Fully Fixed)
 */
document.addEventListener('DOMContentLoaded', () => {
  const navToggle = document.getElementById('cyberNavToggle');
  const mainNav = document.getElementById('cyberMainNav');
  const gamesDropdown = document.getElementById('cyberGamesDropdown');
  const gamesDropdownTrigger = document.getElementById('cyberGamesTrigger');

  const desktopMedia = window.matchMedia('(min-width: 901px)');

  function playClickSfx(freq = 600) {
    if (typeof window.playTone === 'function' && !window.isMuted) {
      window.playTone(freq, 0.04, 'sine', 0.04);
    }
  }

  /* --------------------------------------------------------------------------
     MOBILE NAVIGATION DRAWER
     -------------------------------------------------------------------------- */
  function setNavState(isOpen) {
    if (!navToggle || !mainNav) return;

    navToggle.setAttribute('aria-expanded', String(isOpen));
    mainNav.classList.toggle('nav-open', isOpen);
    navToggle.classList.toggle('active', isOpen);
    document.body.classList.toggle('nav-locked', isOpen);

    if (isOpen) {
      playClickSfx(720);
      const firstFocusable = mainNav.querySelector('a, button');
      if (firstFocusable) firstFocusable.focus();
    } else {
      playClickSfx(480);
      closeGamesDropdown();
    }
  }

  if (navToggle && mainNav) {
    navToggle.addEventListener('click', (e) => {
      e.stopPropagation();
      const isExpanded = navToggle.getAttribute('aria-expanded') === 'true';
      setNavState(!isExpanded);
    });
  }

  /* --------------------------------------------------------------------------
     GAMES DROPDOWN LOGIC
     -------------------------------------------------------------------------- */
  function setDropdownState(isOpen) {
    if (!gamesDropdown || !gamesDropdownTrigger) return;
    gamesDropdown.classList.toggle('dropdown-open', isOpen);
    gamesDropdownTrigger.setAttribute('aria-expanded', String(isOpen));
  }

  function closeGamesDropdown() {
    setDropdownState(false);
  }

  if (gamesDropdown && gamesDropdownTrigger) {
    gamesDropdownTrigger.addEventListener('click', (e) => {
      e.preventDefault();
      e.stopPropagation();
      const isOpen = gamesDropdown.classList.contains('dropdown-open');
      setDropdownState(!isOpen);
      playClickSfx(isOpen ? 520 : 680);
    });
  }

  /* --------------------------------------------------------------------------
     KEYBOARD ACCESSIBILITY (ESC, TAB-TRAP, ARROWS)
     -------------------------------------------------------------------------- */
  document.addEventListener('keydown', (e) => {
    const isNavOpen = mainNav && mainNav.classList.contains('nav-open');
    const isDropdownOpen = gamesDropdown && gamesDropdown.classList.contains('dropdown-open');

    // 1. ESC Key
    if (e.key === 'Escape') {
      if (isDropdownOpen) {
        closeGamesDropdown();
        if (gamesDropdownTrigger) gamesDropdownTrigger.focus();
      }
      if (isNavOpen && !desktopMedia.matches) {
        setNavState(false);
        if (navToggle) navToggle.focus();
      }
      return;
    }

    // 2. Focus Trap inside Mobile Drawer
    if (e.key === 'Tab' && isNavOpen && !desktopMedia.matches) {
      const focusables = Array.from(
        mainNav.querySelectorAll('a[href], button:not([disabled])')
      ).filter(el => el.offsetParent !== null); // Filter visible elements

      if (focusables.length === 0) return;

      const firstEl = focusables[0];
      const lastEl = focusables[focusables.length - 1];

      if (e.shiftKey && document.activeElement === firstEl) {
        e.preventDefault();
        lastEl.focus();
      } else if (!e.shiftKey && document.activeElement === lastEl) {
        e.preventDefault();
        firstEl.focus();
      }
    }

    // 3. Arrow Navigation in Dropdown (Fixed initial index)
    if (isDropdownOpen && gamesDropdown) {
      const dropdownLinks = Array.from(gamesDropdown.querySelectorAll('.cyber-dropdown-link'));
      if (dropdownLinks.length === 0) return;

      const currentIndex = dropdownLinks.indexOf(document.activeElement);

      if (e.key === 'ArrowDown') {
        e.preventDefault();
        const nextIndex = currentIndex === -1 ? 0 : (currentIndex + 1) % dropdownLinks.length;
        dropdownLinks[nextIndex].focus();
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        const prevIndex = currentIndex <= 0 ? dropdownLinks.length - 1 : currentIndex - 1;
        dropdownLinks[prevIndex].focus();
      }
    }
  });

  /* --------------------------------------------------------------------------
     OUTSIDE CLICK LISTENER
     -------------------------------------------------------------------------- */
  document.addEventListener('click', (e) => {
    if (gamesDropdown && !gamesDropdown.contains(e.target)) {
      closeGamesDropdown();
    }
    if (mainNav && navToggle && !desktopMedia.matches) {
      if (!mainNav.contains(e.target) && !navToggle.contains(e.target)) {
        if (mainNav.classList.contains('nav-open')) {
          setNavState(false);
        }
      }
    }
  });

  /* --------------------------------------------------------------------------
     PAGE NAVIGATION LINKS (EXCLUDES DROPDOWN BUTTON TRIGGER)
     -------------------------------------------------------------------------- */
  if (mainNav) {
    const pageNavLinks = mainNav.querySelectorAll('a[href]');
    pageNavLinks.forEach((link) => {
      link.addEventListener('click', () => {
        if (!desktopMedia.matches) {
          setNavState(false);
        }
      });
    });
  }

  /* --------------------------------------------------------------------------
     VIEWPORT MEDIA LISTENER
     -------------------------------------------------------------------------- */
  desktopMedia.addEventListener('change', (e) => {
    if (e.matches && mainNav && mainNav.classList.contains('nav-open')) {
      setNavState(false);
    }
  });
});
