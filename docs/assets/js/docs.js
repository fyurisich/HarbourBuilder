// HarbourBuilder Documentation - JavaScript
// Theme toggle, search, copy code, navigation, TOC rail

// Theme toggle
function toggleTheme() {
  const html = document.documentElement;
  const current = html.getAttribute('data-theme');
  const next = current === 'light' ? 'dark' : 'light';
  html.setAttribute('data-theme', next);
  localStorage.setItem('hb-theme', next);
  document.querySelector('.theme-toggle').textContent = next === 'light' ? '\u263E' : '\u2600';
}

// Init theme
(function() {
  const saved = localStorage.getItem('hb-theme') || 'dark';
  document.documentElement.setAttribute('data-theme', saved);
})();

// Copy code button, active link, TOC rail
document.addEventListener('DOMContentLoaded', function() {
  // Copy code buttons
  document.querySelectorAll('pre').forEach(function(block) {
    var btn = document.createElement('button');
    btn.className = 'copy-btn';
    btn.textContent = 'Copy';
    btn.onclick = function() {
      navigator.clipboard.writeText(block.textContent.replace('Copy', '').trim());
      btn.textContent = 'Copied!';
      setTimeout(function() { btn.textContent = 'Copy'; }, 2000);
    };
    block.style.position = 'relative';
    block.appendChild(btn);
  });

  // Active sidebar link
  var path = window.location.pathname;
  document.querySelectorAll('.sidebar a').forEach(function(a) {
    if (a.getAttribute('href') && path.indexOf(a.getAttribute('href')) >= 0)
      a.classList.add('active');
  });

  // TOC Rail - Scroll spy and smooth scroll
  var tocRail = document.querySelector('.toc-rail');
  if (!tocRail) return;

  var headings = document.querySelectorAll('.content h2[id], .content h3[id]');
  var tocLinks = tocRail.querySelectorAll('a');

  if (headings.length === 0 || tocLinks.length === 0) return;

  // Smooth scroll on click
  tocLinks.forEach(function(link) {
    link.addEventListener('click', function(e) {
      e.preventDefault();
      var targetId = this.getAttribute('href').substring(1);
      var targetEl = document.getElementById(targetId);
      if (targetEl) {
        var headerOffset = 80;
        var elementPosition = targetEl.getBoundingClientRect().top;
        var offsetPosition = elementPosition + window.pageYOffset - headerOffset;
        window.scrollTo({ top: offsetPosition, behavior: 'smooth' });
      }
    });
  });

  // Scroll spy - highlight current section
  function updateActiveLink() {
    var currentHeading = null;
    var scrollPos = window.scrollY + 100;

    headings.forEach(function(heading) {
      if (heading.offsetTop <= scrollPos) {
        currentHeading = heading;
      }
    });

    if (currentHeading) {
      tocLinks.forEach(function(link) {
        link.classList.remove('active');
        if (link.getAttribute('href') === '#' + currentHeading.id) {
          link.classList.add('active');
        }
      });
    }
  }

  window.addEventListener('scroll', updateActiveLink);
  updateActiveLink();
});

// Simple search filter
function doSearch(query) {
  query = query.toLowerCase();
  document.querySelectorAll('.sidebar a').forEach(function(a) {
    var text = a.textContent.toLowerCase();
    a.style.display = text.indexOf(query) >= 0 || query === '' ? '' : 'none';
  });
}
