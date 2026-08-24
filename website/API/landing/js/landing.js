(function () {
    'use strict';

    var html = document.documentElement;
    var header = document.getElementById('siteHeader');
    var menuToggle = document.getElementById('menuToggle');
    var mobileMenu = document.getElementById('mobileMenu');
    var themeToggle = document.getElementById('themeToggle');
    var reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    function setTheme(theme) {
        html.setAttribute('data-theme', theme);
        localStorage.setItem('echo-theme', theme);
        themeToggle.setAttribute('aria-label', theme === 'dark' ? '切换浅色模式' : '切换深色模式');
        themeToggle.innerHTML = theme === 'dark'
            ? '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4M2 12h2m16 0h2M4.9 19.1l1.4-1.4M18.1 5.1l1.4-1.4"/></svg>'
            : '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M21 12.8A8.5 8.5 0 1 1 11.2 3 6.7 6.7 0 0 0 21 12.8Z"/></svg>';
    }

    var storedTheme = localStorage.getItem('echo-theme');
    var systemDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
    setTheme(storedTheme || (systemDark ? 'dark' : 'light'));
    themeToggle.addEventListener('click', function () {
        setTheme(html.getAttribute('data-theme') === 'dark' ? 'light' : 'dark');
    });

    function setMenu(open) {
        mobileMenu.classList.toggle('open', open);
        menuToggle.classList.toggle('open', open);
        menuToggle.setAttribute('aria-expanded', open ? 'true' : 'false');
        menuToggle.setAttribute('aria-label', open ? '关闭菜单' : '打开菜单');
    }
    menuToggle.addEventListener('click', function () { setMenu(!mobileMenu.classList.contains('open')); });
    mobileMenu.querySelectorAll('a').forEach(function (link) { link.addEventListener('click', function () { setMenu(false); }); });
    document.addEventListener('keydown', function (event) { if (event.key === 'Escape') setMenu(false); });

    document.querySelectorAll('a[href^="#"]').forEach(function (link) {
        link.addEventListener('click', function (event) {
            var target = document.querySelector(link.getAttribute('href'));
            if (!target) return;
            event.preventDefault();
            target.scrollIntoView({ behavior: reducedMotion ? 'auto' : 'smooth', block: 'start' });
        });
    });

    function updateHeader() { header.classList.toggle('scrolled', window.scrollY > 18); }
    updateHeader();
    window.addEventListener('scroll', updateHeader, { passive: true });

    var revealItems = document.querySelectorAll('.reveal');
    if ('IntersectionObserver' in window && !reducedMotion) {
        var observer = new IntersectionObserver(function (entries) {
            entries.forEach(function (entry) {
                if (!entry.isIntersecting) return;
                entry.target.classList.add('visible');
                observer.unobserve(entry.target);
            });
        }, { threshold: 0.12, rootMargin: '0px 0px -28px' });
        revealItems.forEach(function (item) { observer.observe(item); });
    } else {
        revealItems.forEach(function (item) { item.classList.add('visible'); });
    }

    function fetchLatestVersion(platform) {
        return fetch('/api/v1/update/versions?platform=' + encodeURIComponent(platform), { headers: { Accept: 'application/json' } })
            .then(function (response) { if (!response.ok) throw new Error('version request failed'); return response.json(); })
            .then(function (json) { return json.code === 0 && json.data && json.data.length ? json.data[0] : null; });
    }

    fetchLatestVersion('android').then(function (version) {
        if (!version) return;
        document.querySelectorAll('[data-app-version]').forEach(function (element) { element.textContent = 'v' + version.version; });
        document.querySelectorAll('[data-download-link]').forEach(function (link) { link.href = version.download_url; });
    }).catch(function () { /* 保留静态版本和默认下载地址 */ });

    document.querySelectorAll('[data-download-link]').forEach(function (link) {
        link.addEventListener('click', function (event) {
            if (!/iPhone|iPad|iPod/i.test(navigator.userAgent)) return;
            event.preventDefault();
            fetchLatestVersion('ios').then(function (version) {
                if (version && version.download_url) window.location.href = version.download_url;
                else window.alert('iOS 版本尚未发布，请先使用 Android 版本。');
            }).catch(function () { window.alert('暂时无法获取 iOS 版本，请稍后再试。'); });
        });
    });
}());
