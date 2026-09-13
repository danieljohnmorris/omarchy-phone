// MAIN-world content script: patch User-Agent Client Hints so sites that
// sniff navigator.userAgentData (instead of the UA string) see a mobile
// device. Values mirror the --user-agent flag in chromium-flags.conf:
// Pixel 7, Android 14, Chrome 152.
(() => {
  const d = navigator.userAgentData;
  if (!d) return;

  const spoof = Object.create(d);
  Object.defineProperty(spoof, "mobile", { value: true });
  Object.defineProperty(spoof, "platform", { value: "Android" });
  Object.defineProperty(spoof, "brands", {
    value: Object.freeze([
      { brand: "Chromium", version: "152" },
      { brand: "Google Chrome", version: "152" },
      { brand: "Not:A-Brand", version: "24" }
    ])
  });
  spoof.getHighEntropyValues = hints => {
    const all = {
      architecture: "arm",
      bitness: "64",
      model: "Pixel 7",
      platformVersion: "14.0.0",
      uaFullVersion: "152.0.0.0",
      fullVersionList: [
        { brand: "Chromium", version: "152.0.0.0" },
        { brand: "Google Chrome", version: "152.0.0.0" },
        { brand: "Not:A-Brand", version: "24.0.0.0" }
      ],
      mobile: true,
      platform: "Android",
      wow64: false,
      formFactors: ["Mobile"]
    };
    const out = {};
    (hints || []).forEach(h => { if (h in all) out[h] = all[h] });
    return Promise.resolve(out);
  };
  Object.defineProperty(spoof, "toJSON", { value: d.toJSON.bind(d) });

  Object.defineProperty(navigator, "userAgentData", {
    get: () => spoof,
    configurable: true
  });
  Object.defineProperty(navigator, "platform", {
    get: () => "Linux armv8l",
    configurable: true
  });
})();
