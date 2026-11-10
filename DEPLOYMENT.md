# Static deployment notes

This package is designed for GitHub Pages and Cloudflare Pages/Workers.

## GitHub Pages

1. Push the contents of this folder to a repository.
2. In **Settings → Pages**, choose **Deploy from a branch**.
3. Select the branch and `/root` folder.
4. All links use relative paths (`./...`), so project pages work even when hosted below a repository subpath.

## Cloudflare Pages

1. Create a Pages project connected to the GitHub repository.
2. Framework preset: **None**.
3. Build command: leave blank.
4. Output directory: `/` or the repository root.
5. Cloudflare Pages automatically reads `_headers` and `404.html`.

## Cloudflare Workers Static Assets

If using Workers with static assets, serve the repository root as the assets directory. The site has no server-side runtime requirement and does not depend on a framework build step.
