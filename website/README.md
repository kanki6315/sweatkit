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
