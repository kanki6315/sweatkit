# SweatKit website

A buildless static site for Cloudflare Workers. Edit the HTML in `public/` and the shared `public/styles.css`. No runtime JavaScript, fonts, cookies, or analytics are loaded.

## Preview and deploy

From this directory:

```sh
npm install
npm run dev
npm run check
npm run deploy
```

Wrangler prompts for Cloudflare authentication when necessary. For Cloudflare Workers Git builds, set the root directory to `website`, leave the build command empty, and use `npm run deploy` as the deploy command.

Add your full hostname in Cloudflare → Workers & Pages → sweatkit-site → Settings → Domains & Routes → Custom Domain. The hostname was supplied as `sweatkit.arjunakankipati`; no domain suffix is assumed or bound in configuration.

Submission URLs, after deployment:

- Marketing: `https://<your-hostname>/`
- Support: `https://<your-hostname>/support`
- Privacy: `https://<your-hostname>/privacy`

The privacy text describes the current local-first implementation. Review it against the release being submitted and update it if data handling changes. The pages alone do not establish Apple or Garmin approval.

## App theme

The site extends the native app's system typography, neutral light/dark surfaces, cyan interaction color, and rounded navigation. The landing page and favicons reuse the route and endpoint artwork from `App/SweatKit.icon/Assets/`, flattened into the two SVGs in `public/assets/`. These are static web renditions; they do not reproduce iOS Icon Composer lighting. Keep the app's source icon layers unchanged when editing the website.

## Contact links

Keep the `<!--email_off-->` and `<!--/email_off-->` comments around the entire email link on support and privacy pages. These opt out of Cloudflare Email Address Obfuscation, preserving both the visible address and `mailto:` destination without a decode script (the site intentionally blocks scripts through CSP). Do not strip these comments during future HTML minification.
