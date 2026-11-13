document.addEventListener('DOMContentLoaded', () => {
  // Checksum Accordion Toggle
  const checksumToggle = document.getElementById('checksumToggle');
  const checksumContent = document.getElementById('checksumContent');

  if (checksumToggle && checksumContent) {
    checksumToggle.addEventListener('click', () => {
      const isHidden = checksumContent.classList.contains('hidden');
      checksumContent.classList.toggle('hidden');
      const arrow = checksumToggle.querySelector('.arrow-icon');
      if (arrow) {
        arrow.textContent = isHidden ? '▴' : '▾';
      }
    });
  }

  // Copy Checksum buttons
  document.querySelectorAll('.btn-copy').forEach((btn) => {
    btn.addEventListener('click', () => {
      const targetId = btn.getAttribute('data-target');
      const codeEl = document.getElementById(targetId);
      if (codeEl) {
        const text = codeEl.textContent.trim();
        navigator.clipboard.writeText(text).then(() => {
          const original = btn.textContent;
          btn.textContent = 'Đã copy!';
          btn.style.color = '#34d399';
          setTimeout(() => {
            btn.textContent = original;
            btn.style.color = '';
          }, 2000);
        });
      }
    });
  });

  // Interactive Window Tab Toggle
  const tabAppsBtn = document.getElementById('tabAppsBtn');
  const tabTrashBtn = document.getElementById('tabTrashBtn');
  const previewTabApps = document.getElementById('previewTabApps');
  const previewTabTrash = document.getElementById('previewTabTrash');

  if (tabAppsBtn && tabTrashBtn && previewTabApps && previewTabTrash) {
    tabAppsBtn.addEventListener('click', () => {
      tabAppsBtn.classList.add('active');
      tabTrashBtn.classList.remove('active');
      previewTabApps.classList.remove('hidden');
      previewTabTrash.classList.add('hidden');
    });

    tabTrashBtn.addEventListener('click', () => {
      tabTrashBtn.classList.add('active');
      tabAppsBtn.classList.remove('active');
      previewTabTrash.classList.remove('hidden');
      previewTabApps.classList.add('hidden');
    });
  }
});
