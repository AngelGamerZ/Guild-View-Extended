const path = require("path");
const { pathToFileURL } = require("url");
const { chromium } = require("playwright");

(async () => {
  const root = path.resolve(__dirname, "..");
  const source = path.join(root, "docs", "screenshots", "render.html");
  const browser = await chromium.launch({
    headless: true,
    executablePath: process.env.GVE_CHROME || "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
  });
  const page = await browser.newPage({
    viewport: { width: 1120, height: 700 },
    deviceScaleFactor: 2,
  });
  await page.goto(pathToFileURL(source).href, { waitUntil: "networkidle" });
  await page.evaluate(async () => {
    await Promise.all(Array.from(document.images).map((image) => {
      if (image.complete) return Promise.resolve();
      return new Promise((resolve) => {
        image.addEventListener("load", resolve, { once: true });
        image.addEventListener("error", resolve, { once: true });
      });
    }));
  });
  for (const name of ["members", "details", "professions"]) {
    await page.locator(`#${name}`).screenshot({
      path: path.join(root, "docs", "screenshots", `${name}.png`),
    });
  }
  await browser.close();
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
