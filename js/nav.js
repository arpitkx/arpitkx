/**
 * CYBERTYPER - Shared Header Navigation & Dropdown Controller
 * Features:
 * - Mobile drawer toggle with focus-trapping & background inertness
 * - Fully accessible ARIA dropdown with ArrowUp / ArrowDown navigation
 * - matchMedia listener (replaces heavy resize events)
 * - Safe integration with Web Audio API sound feedback
 */
document.addEventListener('DOMContentLoaded', () => {
  const navToggle = document.getElementById('cyberNavToggle');
  const mainNav = document.getElementById('cyberMainNav');
  const gamesDropdown = document.getElementById('cyberGamesDropdown');
  const gamesDropdownTrigger = document.getElementById('cyberGamesTrigger');

  const desktopMedia = window.matchMedia('(min-width: 901px)');

  // Helper: Play SFX if defined in main script
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
      // First interactive element par focus shift
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
     ACCESSIBILITY: KEYBOARD NAVIGATION (ESC, TAB-TRAP, ARROWS)
     -------------------------------------------------------------------------- */
  document.addEventListener('keydown', (e) => {
    const isNavOpen = mainNav && mainNav.classList.contains('nav-open');
    const isDropdownOpen = gamesDropdown && gamesDropdown.classList.contains('dropdown-open');

    // 1. ESC Key: Close whichever menu is open
    if (e.key === 'Escape') {
      if (isDropdownOpen) {
        closeGamesDropdown();
        gamesDropdownTrigger.focus();
      }
      if (isNavOpen && !desktopMedia.matches) {
        setNavState(false);
        navToggle.focus();
      }
      return;
    }

    // 2. Tab Trap inside Mobile Navigation
    if (e.key === 'Tab' && isNavOpen && !desktopMedia.matches) {
      const focusables = Array.from(mainNav.querySelectorAll('a, button:not([disabled])'));
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

    // 3. Arrow Down / Up Navigation inside Games Dropdown
    if (isDropdownOpen && gamesDropdown) {
      const dropdownLinks = Array.from(gamesDropdown.querySelectorAll('.cyber-dropdown-link'));
      const currentIndex = dropdownLinks.indexOf(document.activeElement);

      if (e.key === 'ArrowDown') {
        e.preventDefault();
        const nextIndex = (currentIndex + 1) % dropdownLinks.length;
        dropdownLinks[nextIndex].focus();
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        const prevIndex = (currentIndex - 1 + dropdownLinks.length) % dropdownLinks.length;
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
     LINK SELECTION & SCREEN-RESIZE HANDLING
     -------------------------------------------------------------------------- */
  // Mobile drawer me link click hone par close karna
  if (mainNav) {
    const navLinks = mainNav.querySelectorAll('a:not(#cyberGamesTrigger)');
    navLinks.forEach((link) => {
      link.addEventListener('click', () => {
        if (!desktopMedia.matches) {
          setNavState(false);
        }
      });
    });
  }

  // Optimized viewport listener via matchMedia (no window resize lag)
  desktopMedia.addEventListener('change', (e) => {
    if (e.matches && mainNav && mainNav.classList.contains('nav-open')) {
      setNavState(false);
    }
  });
});
