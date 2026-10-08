// Universal links: tapping a /c/<slug> link on a device with the app opens it in the app.
// Without the app, the same link can open the App Clip.
const APP_ID = "YZ36Z8GSEN.com.countdownula.app";
const CLIP_ID = "YZ36Z8GSEN.com.countdownula.app.Clip";

export const dynamic = "force-static";

export function GET() {
  return Response.json({
    applinks: {
      details: [{ appIDs: [APP_ID], components: [{ "/": "/c/*", comment: "Shared countdown pages" }] }],
    },
    appclips: { apps: [CLIP_ID] },
  });
}
