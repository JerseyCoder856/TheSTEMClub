/* main.js — STEM Club shared JS */

document.addEventListener('DOMContentLoaded', () => {
  const paypalLink = 'PASTE_PAYPAL_URL_HERE';
  const paypalFallbackLink = 'https://www.paypal.com/donate';

  const buildPaypalLink = amount => {
    const configuredLink = paypalLink.trim();
    const baseLink = configuredLink.startsWith('http') ? configuredLink : paypalFallbackLink;
    if (!amount) return baseLink;

    try {
      const url = new URL(baseLink, window.location.origin);
      url.searchParams.set('amount', amount);
      return url.toString();
    } catch (error) {
      const separator = baseLink.includes('?') ? '&' : '?';
      return `${baseLink}${separator}amount=${encodeURIComponent(amount)}`;
    }
  };

  const navbar = document.querySelector('.navbar');
  const NAVBAR_COMPACT_THRESHOLD = 24;
  const NAVBAR_EXPAND_THRESHOLD = 4;
  let setNavbarCompact = shouldCompact => {
    if (!navbar) return;
    navbar.classList.toggle('navbar--compact', shouldCompact);
    setNavOffset();
  };
  const setNavOffset = () => {
    if (!navbar) return;
    document.documentElement.style.setProperty('--nav-scroll-offset', `${navbar.offsetHeight + 24}px`);
  };

  if (navbar) {
    let ticking = false;
    let isNavbarCompact = navbar.classList.contains('navbar--compact');

    setNavbarCompact = shouldCompact => {
      if (shouldCompact === isNavbarCompact) return;
      isNavbarCompact = shouldCompact;
      navbar.classList.toggle('navbar--compact', shouldCompact);
      setNavOffset();
    };

    const updateNavbar = () => {
      const currentScrollY = Math.max(window.scrollY, 0);
      const shouldCompact = isNavbarCompact
        ? currentScrollY > NAVBAR_EXPAND_THRESHOLD
        : currentScrollY > NAVBAR_COMPACT_THRESHOLD;

      setNavbarCompact(shouldCompact);
      ticking = false;
    };

    updateNavbar();
    setNavOffset();
    window.addEventListener('scroll', () => {
      if (!ticking) {
        window.requestAnimationFrame(updateNavbar);
        ticking = true;
      }
    }, { passive: true });
    window.addEventListener('resize', setNavOffset);
    window.addEventListener('load', setNavOffset);
    navbar.addEventListener('transitionend', setNavOffset);
  }

  const navLinks = [...document.querySelectorAll('.nav-links a:not(.btn-donate):not(.nav-cart)')];
  const normalizePath = path => path.replace(/\/$/, '/index.html');
  const samePagePath = url => normalizePath(url.pathname) === normalizePath(window.location.pathname);
  const setActiveNav = () => {
    const currentHash = window.location.hash;
    navLinks.forEach(link => link.classList.remove('active'));

    const hashMatch = currentHash
      ? navLinks.find(link => {
          const url = new URL(link.href);
          return samePagePath(url) && url.hash === currentHash;
        })
      : null;

    const pageMatch = navLinks.find(link => {
      const url = new URL(link.href);
      return samePagePath(url) && !url.hash;
    });

    (hashMatch || pageMatch)?.classList.add('active');
  };

  setActiveNav();
  window.addEventListener('hashchange', setActiveNav);

  const sectionLinks = navLinks
    .map(link => ({ link, url: new URL(link.href) }))
    .filter(({ url }) => samePagePath(url) && url.hash && document.querySelector(url.hash));

  if (sectionLinks.length) {
    const sectionObserver = new IntersectionObserver(entries => {
      const visible = entries
        .filter(entry => entry.isIntersecting)
        .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
      if (!visible) return;
      navLinks.forEach(link => link.classList.remove('active'));
      sectionLinks.find(({ url }) => url.hash === `#${visible.target.id}`)?.link.classList.add('active');
    }, { rootMargin: '-35% 0px -50% 0px', threshold: [0.15, 0.35, 0.6] });

    sectionLinks.forEach(({ url }) => sectionObserver.observe(document.querySelector(url.hash)));
  }

  document.querySelectorAll('form').forEach(form => {
    if (form.classList.contains('payment-form')) return;
    form.addEventListener('submit', e => {
      e.preventDefault();
      if (form.matches('[data-mailto-form]')) {
        const data = new FormData(form);
        const recipient = form.dataset.recipient;
        const name = `${data.get('firstName') || ''} ${data.get('lastName') || ''}`.trim();
        const subject = encodeURIComponent(`Website inquiry from ${name || 'a STEM Club visitor'}`);
        const body = encodeURIComponent(`Name: ${name}\nEmail: ${data.get('email') || ''}\n\n${data.get('message') || ''}`);
        window.location.href = `mailto:${recipient}?subject=${subject}&body=${body}`;
        return;
      }
      const btn = form.querySelector('button[type="submit"]');
      if (!btn) return;
      const orig = btn.textContent;
      btn.textContent = '✅ Submitted!';
      btn.style.background = '#5CBF2A';
      setTimeout(() => {
        btn.textContent = orig;
        btn.style.background = '';
        form.reset();
      }, 3000);
    });
  });

  const getDonationAmount = () => document.querySelector('[data-donation-custom]')?.value || '';
  const syncDonationAmount = amount => {
    document.querySelectorAll('[data-donation-custom], [data-payment-amount]').forEach(input => { input.value = amount; });
    document.querySelectorAll('[data-paypal-amount]').forEach(input => { input.value = amount; });
    document.querySelectorAll('[data-paypal-donate]').forEach(link => {
      link.href = buildPaypalLink(amount);
    });
  };

  document.querySelectorAll('[data-donation-amounts] button').forEach(button => {
    button.addEventListener('click', () => {
      document.querySelectorAll('[data-donation-amounts] button').forEach(btn => btn.classList.remove('is-selected'));
      button.classList.add('is-selected');
      syncDonationAmount(button.dataset.amount || button.textContent.replace('$', ''));
    });
  });

  document.querySelectorAll('[data-donation-custom], [data-payment-amount]').forEach(input => {
    input.addEventListener('input', () => syncDonationAmount(input.value));
  });

  syncDonationAmount(getDonationAmount());

  document.querySelectorAll('[data-paypal-form]').forEach(form => {
    form.addEventListener('submit', event => {
      event.preventDefault();
      const amount = form.querySelector('[data-paypal-amount]')?.value || getDonationAmount();
      window.open(buildPaypalLink(amount), '_blank', 'noopener');
    });
  });

  const cartStorageKey = 'stemClubCart';
  const readCart = () => {
    try { return JSON.parse(localStorage.getItem(cartStorageKey)) || []; }
    catch { return []; }
  };
  let cart = readCart();
  const saveCart = () => localStorage.setItem(cartStorageKey, JSON.stringify(cart));
  const cartItems = document.querySelector('[data-cart-items]');
  const cartTotal = document.querySelector('[data-cart-total]');
  const cartCounts = document.querySelectorAll('[data-cart-count]');
  const cartDrawer = document.querySelector('[data-cart-drawer]');
  const cartNavLinks = document.querySelectorAll('[data-cart-nav]');
  const cartClose = document.querySelector('[data-cart-close]');

  function cartTotalAmount() {
    return cart.reduce((sum, item) => sum + item.price, 0);
  }

  function renderCart() {
    const totals = cartTotalAmount();
    cartCounts.forEach(count => { count.textContent = String(cart.length); });
    if (cartTotal) cartTotal.textContent = `$${totals}`;
    if (cart.length && document.querySelector('[data-payment-amount]') && !getDonationAmount()) syncDonationAmount(String(totals));

    if (!cartItems) return;
    if (!cart.length) {
      cartItems.innerHTML = '<p class="empty-cart">No items yet.</p>';
      return;
    }

    cartItems.innerHTML = cart.map((item, index) => `
      <div class="cart-line">
        <img src="${item.image}" alt="${item.name}">
        <span>${item.name}</span>
        <strong>$${item.price}</strong>
        <button type="button" class="cart-remove" data-cart-remove="${index}" aria-label="Remove ${item.name} from cart">×</button>
      </div>
    `).join('');
  }

  cartItems?.addEventListener('click', event => {
    const removeButton = event.target.closest('[data-cart-remove]');
    if (!removeButton) return;

    const itemIndex = Number(removeButton.dataset.cartRemove);
    if (!Number.isInteger(itemIndex) || !cart[itemIndex]) return;

    cart.splice(itemIndex, 1);
    saveCart();
    renderCart();
  });

  cartNavLinks.forEach(link => {
    link.addEventListener('click', event => {
      if (!cart.length) return;
      if (cartDrawer) {
        event.preventDefault();
        cartDrawer.classList.add('is-open');
      }
    });
  });

  cartClose?.addEventListener('click', () => cartDrawer?.classList.remove('is-open'));

  document.querySelectorAll('.shop-card .shop-btn').forEach(button => {
    button.addEventListener('click', () => {
      const card = button.closest('.shop-card');
      if (!card) return;
      const image = card.querySelector('img')?.getAttribute('src') || '';
      cart.push({
        name: card.dataset.name || 'Shop item',
        price: Number(card.dataset.price || 0),
        image
      });
      saveCart();
      renderCart();
      cartDrawer?.classList.add('is-open');
      button.textContent = 'Added ✓';
      setTimeout(() => { button.textContent = 'Add'; }, 1200);
    });
  });

  renderCart();

  const scrollToSectionTop = (target, behavior = 'smooth') => {
    const targetTop = target.getBoundingClientRect().top + window.scrollY;
    const willUseCompactNav = navbar && targetTop > NAVBAR_COMPACT_THRESHOLD;
    setNavbarCompact(Boolean(willUseCompactNav));
    const scrollOffset = navbar ? navbar.offsetHeight : 0;
    window.scrollTo({
      top: Math.max(targetTop - scrollOffset, 0),
      behavior
    });
  };

  document.querySelectorAll('a[href*="#"]').forEach(anchor => {
    anchor.addEventListener('click', e => {
      const url = new URL(anchor.href);
      if (!url.hash || url.hash === '#' || !samePagePath(url)) return;

      const target = document.querySelector(url.hash);
      if (target) {
        e.preventDefault();
        scrollToSectionTop(target);
        history.pushState(null, '', url.hash);
        setActiveNav();
      }
    });
  });

  if (window.location.hash) {
    const target = document.querySelector(window.location.hash);
    if (target) {
      window.requestAnimationFrame(() => scrollToSectionTop(target, 'auto'));
      window.addEventListener('load', () => scrollToSectionTop(target, 'auto'), { once: true });
    }
  }
});
