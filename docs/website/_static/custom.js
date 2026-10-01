// Add GitHub link to left sidebar above search bar
document.addEventListener('DOMContentLoaded', function() {
    console.log('Custom JS loaded');

    // Find the sidebar search container
    const sidebarSearchContainer = document.querySelector('.sidebar-drawer .sidebar-search-container');
    console.log('Sidebar search container found:', !!sidebarSearchContainer);

    if (sidebarSearchContainer) {
        const githubLink = document.createElement('div');
        githubLink.style.padding = '0.75rem 1rem';
        githubLink.innerHTML = `
            <a href="https://github.com/open-component-model/open-delivery-gear"
               target="_blank"
               class="github-link-sidebar"
               aria-label="GitHub Repository"
               style="display: flex; align-items: center; justify-content: center; color: var(--color-foreground-primary); text-decoration: none; transition: color 0.2s;">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" style="width: 22px; height: 22px; fill: currentColor;">
                    <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"></path>
                </svg>
            </a>
        `;

        // Insert before the search container
        sidebarSearchContainer.parentNode.insertBefore(githubLink, sidebarSearchContainer);
        console.log('GitHub link added before search container');

        // Add hover effect
        const link = githubLink.querySelector('a');
        link.addEventListener('mouseenter', function() {
            this.style.color = 'var(--color-link)';
        });
        link.addEventListener('mouseleave', function() {
            this.style.color = 'var(--color-foreground-primary)';
        });
    }

    // Open external card links in new tabs
    document.querySelectorAll('.sd-card a.sd-stretched-link').forEach(function(link) {
        if (link.href.startsWith('http://') || link.href.startsWith('https://')) {
            // Check if it's an external link (not same domain)
            const url = new URL(link.href);
            if (url.hostname !== window.location.hostname) {
                link.setAttribute('target', '_blank');
                link.setAttribute('rel', 'noopener noreferrer');
            }
        }
    });
});
