// Universal links: tapping a /c/<slug> link on a device with the app opens it in the app.
// The App Clip entry joins this file when the clip ships.
const APP_ID = "YZ36Z8GSEN.com.countdownula.app";

export const dynamic = "force-static";

export function GET() {
  return Response.json({
    applinks: {
      details: [{ appIDs: [APP_ID], components: [{ "/": "/c/*", comment: "Shared countdown pages" }] }],
    },
  });
}
