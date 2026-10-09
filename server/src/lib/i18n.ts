// The web pages in the viewer's language: the live page, its coffin and pool panels, embeds, link
// previews and the crypt. The language comes from the browser's Accept-Language header. English
// is the base; the other languages are drafts awaiting review, like the apps' String Catalog.

export const LOCALES = ["en", "ja", "de", "es", "pt-BR", "fr"] as const;
export type Locale = (typeof LOCALES)[number];

/** The best match for an Accept-Language header ("de-CH,de;q=0.9,en;q=0.8"), or English. Pure, for tests. */
export function pickLocale(header: string | null | undefined): Locale {
  if (!header) return "en";
  const wanted = header
    .split(",")
    .map((part, index) => {
      const [tag, ...params] = part.trim().split(";");
      const q = params.map((p) => p.trim()).find((p) => p.startsWith("q="));
      return { tag: tag.toLowerCase(), q: q ? Number(q.slice(2)) || 0 : 1, index };
    })
    .filter((w) => w.tag && w.q > 0)
    .sort((a, b) => b.q - a.q || a.index - b.index);
  for (const { tag } of wanted) {
    const base = tag.split("-")[0];
    // Portuguese from anywhere reads the Brazilian draft; it's closer than English.
    if (base === "pt") return "pt-BR";
    const match = LOCALES.find((l) => l.toLowerCase() === base);
    if (match) return match;
  }
  return "en";
}

/** A message: plain text with {placeholders}, or plural forms chosen by the count `n`. */
type Message = string | { one: string; other: string };

const en = {
  days: "days", hours: "hours", min: "min", sec: "sec",
  itsHere: "It's here!", itsHereOn: "It's here! {date}", since: "Since {date}", expected: "Expected {date}",
  itHappened: "It happened.",
  countingDown: { one: "{n} person is counting down", other: "{n} people are counting down" },
  pitchBefore: "Count down together: it shows up on your Lock Screen, watch and menu bar, and stays in step when it changes.",
  pitchAfter: "Count down to your next big day together: it shows up on your Lock Screen, watch and menu bar.",
  countDownWithMe: "Count down with me", addToCalendar: "Add to Calendar", appleOutlook: "Apple or Outlook Calendar",
  googleCalendar: "Google Calendar", downloadIcs: "Download .ics", addToWallet: "Add to Apple Wallet", getTheApp: "Get the app",
  embedOnSite: "Embed on your site", embedTitle: "Embed this countdown",
  embedBody: "Paste this where the countdown should go. It ticks live and stays in step with the owner's edits.",
  embedOptions: "Options: data-theme=\"dark\" or \"light\" instead of the countdown's own look, and data-end=\"recap\", \"countup\" or \"hide\" for what shows at zero (or data-message=\"Doors are open!\").",
  copy: "Copy", copied: "Copied", done: "Done",
  // Recap
  counted: { one: "{n} day counted", other: "{n} days counted" },
  countedHours: { one: "{n} hour counted", other: "{n} hours counted" },
  ofUs: "{n} of us", countedDown: "{n} counted down",
  notesInCoffin: { one: "{n} note in the coffin", other: "{n} notes in the coffin" },
  guessedClosest: "{names} guessed closest",
  together: "{n} counted down together",
  // Coffin
  coffinOpen: "🦇 The coffin is open", coffinSealed: "🦇 The sealed coffin",
  coffinNothingLeft: "Nobody left anything this time.",
  coffinFromEveryone: { one: "{n} note from everyone who counted down.", other: "{n} notes from everyone who counted down." },
  coffinWasSealed: { one: "{n} note was sealed inside. Everyone who left one, or counted down in the app, can open it.", other: "{n} notes were sealed inside. Everyone who left one, or counted down in the app, can open it." },
  coffinNothingYet: "Nothing sealed yet.", coffinSoFar: "{n} sealed so far.",
  coffinInvite: "Leave a note or a photo. Nobody sees it until zero, then everyone does.",
  yourName: "Your name", yourNote: "Your note", addPhoto: "Add a photo", addPhotos: "Add up to {n} photos",
  changePhoto: "Change photo", changePhotos: "Change photos", photos: "{n} photos",
  sealing: "Sealing…", sealIt: "Seal it", whatYouSealed: "What you sealed", remove: "Remove", report: "Report", reported: "Reported", you: "(you)",
  couldntSeal: "Couldn't seal that. Try again.", couldntReadPhoto: "Couldn't read that photo.", photoTooLarge: "That photo is too large.",
  // Pool
  resultsIn: "The results are in", guessTheDate: "Guess the date",
  calledIt: "{names} called it closest. It happened {date}.", happenedOn: "It happened {date}.",
  guessingClosed: "Guessing is closed. The closest guess wins once the real date is in.",
  guessPrompt: "When do you think it'll happen? The closest guess wins bragging rights.",
  yourGuess: "Your guess", changeGuess: "Change my guess", lockIn: "Lock it in", noGuesses: "No guesses yet. Be the first.",
  couldntSaveGuess: "Couldn't save your guess.", spotOn: "spot on", offBy: "off by {span}",
  // Embed
  madeWith: "Made with", cantEmbed: "This countdown can't be embedded.",
  // Preview images and descriptions
  daysLeft: { one: "{n} day", other: "{n} days" }, toGo: "to go", toGoOn: "to go · {date}",
  sinceLower: "since {date}", andCounting: "and counting",
  // Crypt
  crypt: "The Crypt", cryptOf: "The Crypt: {name}", all: "All",
  cryptDescription: "Countdowns to holidays, eclipses, solstices and big games. Count down together.",
  cryptPitch: "Put them on your Lock Screen, watch and menu bar.", getCountdowncula: "Get Count Downcula",
  cryptEmpty: "Nothing here right now. Check back soon.",
  holidays: "Holidays", sky: "Sky", sports: "Sports", fun: "Fun days",
  notFoundBody: "The link may be wrong, or its owner unpublished it.",
  cryptIntro: "Countdowns worth waiting for. Pick one to count down with everyone else; holidays tick to midnight wherever you are.",
  notFoundTitle: "This countdown has vanished",
  categoryTitle: "{name} countdowns",
  counting: { one: "{n} counting", other: "{n} counting" },
} satisfies Record<string, Message>;

export type Key = keyof typeof en;
type Dictionary = { [K in Key]: (typeof en)[K] extends string ? string : { one: string; other: string } };

const ja: Dictionary = {
  days: "日", hours: "時間", min: "分", sec: "秒",
  itsHere: "その日が来た！", itsHereOn: "その日が来た！ {date}", since: "{date}から", expected: "予想 {date}",
  itHappened: "その日が来ました。",
  countingDown: { one: "{n}人がカウントダウン中", other: "{n}人がカウントダウン中" },
  pitchBefore: "一緒にカウントダウン：ロック画面、Apple Watch、メニューバーに表示され、変更もそのまま反映されます。",
  pitchAfter: "次の大切な日も一緒にカウントダウン：ロック画面、Apple Watch、メニューバーに表示されます。",
  countDownWithMe: "一緒にカウントダウン", addToCalendar: "カレンダーに追加", appleOutlook: "AppleまたはOutlookカレンダー",
  googleCalendar: "Googleカレンダー", downloadIcs: ".icsをダウンロード", addToWallet: "Apple Walletに追加", getTheApp: "アプリを入手",
  embedOnSite: "サイトに埋め込む", embedTitle: "このカウントダウンを埋め込む",
  embedBody: "カウントダウンを表示したい場所に貼り付けてください。リアルタイムで動き、作成者の変更も反映されます。",
  embedOptions: "オプション：data-theme=\"dark\"または\"light\"でカウントダウン本来の見た目の代わりに、data-end=\"recap\"、\"countup\"、\"hide\"でゼロ時の表示を指定できます（data-message=\"開場しました！\"も可）。",
  copy: "コピー", copied: "コピーしました", done: "完了",
  counted: { one: "{n}日カウント", other: "{n}日カウント" },
  countedHours: { one: "{n}時間カウント", other: "{n}時間カウント" },
  ofUs: "{n}人で", countedDown: "{n}人がカウントダウン",
  notesInCoffin: { one: "棺のメッセージ{n}件", other: "棺のメッセージ{n}件" },
  guessedClosest: "一番近かったのは{names}さん", together: "{n}人でカウントダウンしました",
  coffinOpen: "🦇 棺が開きました", coffinSealed: "🦇 封印された棺",
  coffinNothingLeft: "今回は誰も何も残しませんでした。",
  coffinFromEveryone: { one: "カウントダウンしたみんなからのメッセージ{n}件。", other: "カウントダウンしたみんなからのメッセージ{n}件。" },
  coffinWasSealed: { one: "{n}件のメッセージが封印されています。メッセージを残した人とアプリでカウントダウンした人が開けられます。", other: "{n}件のメッセージが封印されています。メッセージを残した人とアプリでカウントダウンした人が開けられます。" },
  coffinNothingYet: "まだ何も封印されていません。", coffinSoFar: "これまでに{n}件封印されています。",
  coffinInvite: "メッセージや写真を残しましょう。ゼロになるまで誰にも見えず、その時みんなに公開されます。",
  yourName: "お名前", yourNote: "メッセージ", addPhoto: "写真を追加", addPhotos: "写真を最大{n}枚追加",
  changePhoto: "写真を変更", changePhotos: "写真を変更", photos: "写真{n}枚",
  sealing: "封印中…", sealIt: "封印する", whatYouSealed: "あなたが封印したもの", remove: "削除", report: "報告", reported: "報告済み", you: "（あなた）",
  couldntSeal: "封印できませんでした。もう一度お試しください。", couldntReadPhoto: "写真を読み込めませんでした。", photoTooLarge: "写真が大きすぎます。",
  resultsIn: "結果発表", guessTheDate: "日付を予想しよう",
  calledIt: "一番近かったのは{names}さん。{date}に起きました。", happenedOn: "{date}に起きました。",
  guessingClosed: "予想の受付は終了しました。実際の日付が決まったら、一番近い予想が勝ちです。",
  guessPrompt: "いつになると思いますか？一番近い予想が自慢できます。",
  yourGuess: "あなたの予想", changeGuess: "予想を変更", lockIn: "決定", noGuesses: "まだ予想はありません。最初の一人になりましょう。",
  couldntSaveGuess: "予想を保存できませんでした。", spotOn: "ぴったり", offBy: "{span}の差",
  madeWith: "Made with", cantEmbed: "このカウントダウンは埋め込めません。",
  daysLeft: { one: "あと{n}日", other: "あと{n}日" }, toGo: "残り", toGoOn: "{date}まで",
  sinceLower: "{date}から", andCounting: "カウント中",
  crypt: "クリプト", cryptOf: "クリプト：{name}", all: "すべて",
  cryptDescription: "祝日、日食、夏至・冬至、大きな試合へのカウントダウン。みんなでカウントダウンしよう。",
  cryptPitch: "ロック画面、Apple Watch、メニューバーに表示できます。", getCountdowncula: "Count Downculaを入手",
  cryptEmpty: "今は何もありません。また後で確認してください。",
  holidays: "祝日", sky: "空", sports: "スポーツ", fun: "楽しい日",
  notFoundBody: "リンクが間違っているか、作成者が公開を停止しました。",
  cryptIntro: "待つ価値のあるカウントダウン。ひとつ選んでみんなと一緒にカウントダウンしましょう。祝日はどこにいても現地の真夜中に向けて進みます。",
  notFoundTitle: "このカウントダウンは消えてしまいました",
  categoryTitle: "{name}のカウントダウン",
  counting: { one: "{n}人がカウント中", other: "{n}人がカウント中" },
};

const de: Dictionary = {
  days: "Tage", hours: "Std.", min: "Min.", sec: "Sek.",
  itsHere: "Es ist so weit!", itsHereOn: "Es ist so weit! {date}", since: "Seit {date}", expected: "Erwartet am {date}",
  itHappened: "Es ist passiert.",
  countingDown: { one: "{n} Person zählt mit", other: "{n} Personen zählen mit" },
  pitchBefore: "Zählt gemeinsam runter: auf dem Sperrbildschirm, der Uhr und in der Menüleiste, und immer synchron, wenn sich etwas ändert.",
  pitchAfter: "Zählt gemeinsam zu eurem nächsten großen Tag runter: auf dem Sperrbildschirm, der Uhr und in der Menüleiste.",
  countDownWithMe: "Zähl mit mir runter", addToCalendar: "Zum Kalender hinzufügen", appleOutlook: "Apple- oder Outlook-Kalender",
  googleCalendar: "Google Kalender", downloadIcs: ".ics laden", addToWallet: "Zu Apple Wallet hinzufügen", getTheApp: "App laden",
  embedOnSite: "Auf deiner Website einbetten", embedTitle: "Diesen Countdown einbetten",
  embedBody: "Füge das dort ein, wo der Countdown erscheinen soll. Er läuft live und bleibt synchron mit den Änderungen des Besitzers.",
  embedOptions: "Optionen: data-theme=\"dark\" oder \"light\" statt des eigenen Looks und data-end=\"recap\", \"countup\" oder \"hide\" für die Anzeige bei null (oder data-message=\"Einlass!\").",
  copy: "Kopieren", copied: "Kopiert", done: "Fertig",
  counted: { one: "{n} Tag gezählt", other: "{n} Tage gezählt" },
  countedHours: { one: "{n} Stunde gezählt", other: "{n} Stunden gezählt" },
  ofUs: "Wir {n}", countedDown: "{n} haben mitgezählt",
  notesInCoffin: { one: "{n} Nachricht im Sarg", other: "{n} Nachrichten im Sarg" },
  guessedClosest: "{names} lag am nächsten dran", together: "{n} haben gemeinsam runtergezählt",
  coffinOpen: "🦇 Der Sarg ist offen", coffinSealed: "🦇 Der versiegelte Sarg",
  coffinNothingLeft: "Diesmal hat niemand etwas hinterlassen.",
  coffinFromEveryone: { one: "{n} Nachricht von allen, die mitgezählt haben.", other: "{n} Nachrichten von allen, die mitgezählt haben." },
  coffinWasSealed: { one: "{n} Nachricht war darin versiegelt. Alle, die etwas hinterlassen oder in der App mitgezählt haben, können ihn öffnen.", other: "{n} Nachrichten waren darin versiegelt. Alle, die etwas hinterlassen oder in der App mitgezählt haben, können ihn öffnen." },
  coffinNothingYet: "Noch nichts versiegelt.", coffinSoFar: "Bisher {n} versiegelt.",
  coffinInvite: "Hinterlasse eine Nachricht oder ein Foto. Bis null sieht es niemand, dann alle.",
  yourName: "Dein Name", yourNote: "Deine Nachricht", addPhoto: "Foto hinzufügen", addPhotos: "Bis zu {n} Fotos hinzufügen",
  changePhoto: "Foto ändern", changePhotos: "Fotos ändern", photos: "{n} Fotos",
  sealing: "Wird versiegelt …", sealIt: "Versiegeln", whatYouSealed: "Was du versiegelt hast", remove: "Entfernen", report: "Melden", reported: "Gemeldet", you: "(du)",
  couldntSeal: "Konnte nicht versiegelt werden. Versuch es noch einmal.", couldntReadPhoto: "Das Foto konnte nicht gelesen werden.", photoTooLarge: "Das Foto ist zu groß.",
  resultsIn: "Das Ergebnis steht fest", guessTheDate: "Tipp das Datum",
  calledIt: "{names} lag am nächsten dran. Es war am {date} so weit.", happenedOn: "Es war am {date} so weit.",
  guessingClosed: "Das Tippen ist beendet. Wer am nächsten dran liegt, gewinnt, sobald das echte Datum feststeht.",
  guessPrompt: "Wann, glaubst du, ist es so weit? Wer am nächsten dran liegt, darf angeben.",
  yourGuess: "Dein Tipp", changeGuess: "Tipp ändern", lockIn: "Festlegen", noGuesses: "Noch keine Tipps. Sei die erste Person.",
  couldntSaveGuess: "Dein Tipp konnte nicht gespeichert werden.", spotOn: "genau richtig", offBy: "{span} daneben",
  madeWith: "Erstellt mit", cantEmbed: "Dieser Countdown kann nicht eingebettet werden.",
  daysLeft: { one: "{n} Tag", other: "{n} Tage" }, toGo: "übrig", toGoOn: "bis zum {date}",
  sinceLower: "seit {date}", andCounting: "und es werden mehr",
  crypt: "Die Gruft", cryptOf: "Die Gruft: {name}", all: "Alle",
  cryptDescription: "Countdowns zu Feiertagen, Finsternissen, Sonnenwenden und großen Spielen. Zählt gemeinsam runter.",
  cryptPitch: "Auf dem Sperrbildschirm, der Uhr und in der Menüleiste.", getCountdowncula: "Count Downcula laden",
  cryptEmpty: "Gerade ist hier nichts. Schau bald wieder vorbei.",
  holidays: "Feiertage", sky: "Himmel", sports: "Sport", fun: "Lustige Tage",
  notFoundBody: "Der Link ist vielleicht falsch, oder der Besitzer hat ihn zurückgezogen.",
  cryptIntro: "Countdowns, auf die sich das Warten lohnt. Wähle einen und zähl mit allen anderen runter; Feiertage laufen überall auf Mitternacht vor Ort zu.",
  notFoundTitle: "Dieser Countdown ist verschwunden",
  categoryTitle: "Countdowns: {name}",
  counting: { one: "{n} zählt mit", other: "{n} zählen mit" },
};

const es: Dictionary = {
  days: "días", hours: "horas", min: "min", sec: "seg",
  itsHere: "¡Ya llegó!", itsHereOn: "¡Ya llegó! {date}", since: "Desde el {date}", expected: "Previsto el {date}",
  itHappened: "Ya pasó.",
  countingDown: { one: "{n} persona cuenta hacia atrás", other: "{n} personas cuentan hacia atrás" },
  pitchBefore: "Cuenta atrás en grupo: aparece en la pantalla bloqueada, el reloj y la barra de menús, y se mantiene al día cuando cambia.",
  pitchAfter: "La cuenta atrás en grupo hasta el próximo gran día: aparece en la pantalla bloqueada, el reloj y la barra de menús.",
  countDownWithMe: "Cuenta conmigo", addToCalendar: "Añadir al calendario", appleOutlook: "Calendario de Apple u Outlook",
  googleCalendar: "Google Calendar", downloadIcs: "Descargar .ics", addToWallet: "Añadir a Apple Wallet", getTheApp: "Obtener la app",
  embedOnSite: "Insertar en tu web", embedTitle: "Insertar esta cuenta atrás",
  embedBody: "Pega esto donde deba ir la cuenta atrás. Avanza en directo y se mantiene al día con los cambios de quien la creó.",
  embedOptions: "Opciones: data-theme=\"dark\" o \"light\" en lugar del aspecto propio, y data-end=\"recap\", \"countup\" o \"hide\" para lo que se ve al llegar a cero (o data-message=\"¡Puertas abiertas!\").",
  copy: "Copiar", copied: "Copiado", done: "Listo",
  counted: { one: "{n} día contado", other: "{n} días contados" },
  countedHours: { one: "{n} hora contada", other: "{n} horas contadas" },
  ofUs: "Somos {n}", countedDown: "{n} contaron hacia atrás",
  notesInCoffin: { one: "{n} nota en el ataúd", other: "{n} notas en el ataúd" },
  guessedClosest: "{names} estuvo más cerca", together: "{n} contaron juntos hacia atrás",
  coffinOpen: "🦇 El ataúd está abierto", coffinSealed: "🦇 El ataúd sellado",
  coffinNothingLeft: "Esta vez nadie dejó nada.",
  coffinFromEveryone: { one: "{n} nota de todos los que contaron.", other: "{n} notas de todos los que contaron." },
  coffinWasSealed: { one: "Había {n} nota sellada dentro. Quien dejó una, o contó en la app, puede abrirlo.", other: "Había {n} notas selladas dentro. Quien dejó una, o contó en la app, puede abrirlo." },
  coffinNothingYet: "Aún no hay nada sellado.", coffinSoFar: "{n} sellados por ahora.",
  coffinInvite: "Deja una nota o una foto. Nadie la ve hasta cero; entonces la ven todos.",
  yourName: "Tu nombre", yourNote: "Tu nota", addPhoto: "Añadir una foto", addPhotos: "Añadir hasta {n} fotos",
  changePhoto: "Cambiar foto", changePhotos: "Cambiar fotos", photos: "{n} fotos",
  sealing: "Sellando…", sealIt: "Sellar", whatYouSealed: "Lo que sellaste", remove: "Quitar", report: "Denunciar", reported: "Denunciado", you: "(tú)",
  couldntSeal: "No se pudo sellar. Inténtalo de nuevo.", couldntReadPhoto: "No se pudo leer esa foto.", photoTooLarge: "Esa foto es demasiado grande.",
  resultsIn: "Ya están los resultados", guessTheDate: "Adivina la fecha",
  calledIt: "{names} estuvo más cerca. Ocurrió el {date}.", happenedOn: "Ocurrió el {date}.",
  guessingClosed: "Las apuestas están cerradas. Gana la más cercana cuando se sepa la fecha real.",
  guessPrompt: "¿Cuándo crees que pasará? La apuesta más cercana gana el derecho a presumir.",
  yourGuess: "Tu apuesta", changeGuess: "Cambiar mi apuesta", lockIn: "Confirmar", noGuesses: "Aún no hay apuestas. Sé el primero.",
  couldntSaveGuess: "No se pudo guardar tu apuesta.", spotOn: "exacto", offBy: "{span} de diferencia",
  madeWith: "Hecho con", cantEmbed: "Esta cuenta atrás no se puede insertar.",
  daysLeft: { one: "{n} día", other: "{n} días" }, toGo: "restantes", toGoOn: "hasta el {date}",
  sinceLower: "desde el {date}", andCounting: "y contando",
  crypt: "La Cripta", cryptOf: "La Cripta: {name}", all: "Todas",
  cryptDescription: "Cuentas atrás para festivos, eclipses, solsticios y grandes partidos. Cuenta con los demás.",
  cryptPitch: "Ponlas en la pantalla bloqueada, el reloj y la barra de menús.", getCountdowncula: "Obtener Count Downcula",
  cryptEmpty: "Ahora no hay nada aquí. Vuelve pronto.",
  holidays: "Festivos", sky: "Cielo", sports: "Deportes", fun: "Días divertidos",
  notFoundBody: "Puede que el enlace esté mal o que quien lo creó haya dejado de compartirlo.",
  cryptIntro: "Cuentas atrás que merecen la espera. Elige una para contar con todos los demás; los festivos llegan a medianoche estés donde estés.",
  notFoundTitle: "Esta cuenta atrás se ha desvanecido",
  categoryTitle: "Cuentas atrás: {name}",
  counting: { one: "{n} contando", other: "{n} contando" },
};

const ptBR: Dictionary = {
  days: "dias", hours: "horas", min: "min", sec: "seg",
  itsHere: "Chegou!", itsHereOn: "Chegou! {date}", since: "Desde {date}", expected: "Previsto para {date}",
  itHappened: "Aconteceu.",
  countingDown: { one: "{n} pessoa está contando", other: "{n} pessoas estão contando" },
  pitchBefore: "Contem juntos: aparece na Tela Bloqueada, no relógio e na barra de menus, e acompanha as mudanças.",
  pitchAfter: "Contem juntos até o próximo grande dia: aparece na Tela Bloqueada, no relógio e na barra de menus.",
  countDownWithMe: "Conte comigo", addToCalendar: "Adicionar ao calendário", appleOutlook: "Calendário Apple ou Outlook",
  googleCalendar: "Google Agenda", downloadIcs: "Baixar .ics", addToWallet: "Adicionar à Apple Wallet", getTheApp: "Obter o app",
  embedOnSite: "Incorporar no seu site", embedTitle: "Incorporar esta contagem",
  embedBody: "Cole isto onde a contagem deve aparecer. Ela corre ao vivo e acompanha as alterações de quem criou.",
  embedOptions: "Opções: data-theme=\"dark\" ou \"light\" no lugar do visual próprio, e data-end=\"recap\", \"countup\" ou \"hide\" para o que aparece no zero (ou data-message=\"Portas abertas!\").",
  copy: "Copiar", copied: "Copiado", done: "OK",
  counted: { one: "{n} dia contado", other: "{n} dias contados" },
  countedHours: { one: "{n} hora contada", other: "{n} horas contadas" },
  ofUs: "Somos {n}", countedDown: "{n} contaram juntos",
  notesInCoffin: { one: "{n} recado no caixão", other: "{n} recados no caixão" },
  guessedClosest: "{names} chegou mais perto", together: "{n} contaram juntos",
  coffinOpen: "🦇 O caixão está aberto", coffinSealed: "🦇 O caixão lacrado",
  coffinNothingLeft: "Desta vez ninguém deixou nada.",
  coffinFromEveryone: { one: "{n} recado de todos que contaram juntos.", other: "{n} recados de todos que contaram juntos." },
  coffinWasSealed: { one: "Havia {n} recado lacrado dentro. Quem deixou um, ou contou no app, pode abrir.", other: "Havia {n} recados lacrados dentro. Quem deixou um, ou contou no app, pode abrir." },
  coffinNothingYet: "Nada lacrado ainda.", coffinSoFar: "{n} lacrados até agora.",
  coffinInvite: "Deixe um recado ou uma foto. Ninguém vê até o zero; aí todos veem.",
  yourName: "Seu nome", yourNote: "Seu recado", addPhoto: "Adicionar uma foto", addPhotos: "Adicionar até {n} fotos",
  changePhoto: "Trocar foto", changePhotos: "Trocar fotos", photos: "{n} fotos",
  sealing: "Lacrando…", sealIt: "Lacrar", whatYouSealed: "O que você lacrou", remove: "Remover", report: "Denunciar", reported: "Denunciado", you: "(você)",
  couldntSeal: "Não foi possível lacrar. Tente de novo.", couldntReadPhoto: "Não foi possível ler essa foto.", photoTooLarge: "Essa foto é grande demais.",
  resultsIn: "Saiu o resultado", guessTheDate: "Adivinhe a data",
  calledIt: "{names} chegou mais perto. Aconteceu em {date}.", happenedOn: "Aconteceu em {date}.",
  guessingClosed: "Os palpites estão encerrados. O mais próximo vence quando a data real for definida.",
  guessPrompt: "Quando você acha que vai acontecer? O palpite mais próximo ganha o direito de se gabar.",
  yourGuess: "Seu palpite", changeGuess: "Mudar meu palpite", lockIn: "Confirmar", noGuesses: "Ainda não há palpites. Seja o primeiro.",
  couldntSaveGuess: "Não foi possível salvar seu palpite.", spotOn: "na mosca", offBy: "{span} de diferença",
  madeWith: "Feito com", cantEmbed: "Esta contagem não pode ser incorporada.",
  daysLeft: { one: "{n} dia", other: "{n} dias" }, toGo: "restantes", toGoOn: "até {date}",
  sinceLower: "desde {date}", andCounting: "e contando",
  crypt: "A Cripta", cryptOf: "A Cripta: {name}", all: "Todas",
  cryptDescription: "Contagens para feriados, eclipses, solstícios e grandes jogos. Contem juntos.",
  cryptPitch: "Coloque na Tela Bloqueada, no relógio e na barra de menus.", getCountdowncula: "Obter o Count Downcula",
  cryptEmpty: "Não há nada aqui agora. Volte em breve.",
  holidays: "Feriados", sky: "Céu", sports: "Esportes", fun: "Dias divertidos",
  notFoundBody: "O link pode estar errado, ou quem criou parou de compartilhar.",
  cryptIntro: "Contagens que valem a espera. Escolha uma para contar com todo mundo; os feriados chegam à meia-noite onde você estiver.",
  notFoundTitle: "Esta contagem desapareceu",
  categoryTitle: "Contagens: {name}",
  counting: { one: "{n} contando", other: "{n} contando" },
};

const fr: Dictionary = {
  days: "jours", hours: "heures", min: "min", sec: "s",
  itsHere: "C’est le jour J !", itsHereOn: "C’est le jour J ! {date}", since: "Depuis le {date}", expected: "Prévu le {date}",
  itHappened: "C’est arrivé.",
  countingDown: { one: "{n} personne fait le compte à rebours", other: "{n} personnes font le compte à rebours" },
  pitchBefore: "Comptez ensemble : sur l’écran verrouillé, la montre et la barre des menus, toujours à jour quand il change.",
  pitchAfter: "Comptez ensemble jusqu’à votre prochain grand jour : sur l’écran verrouillé, la montre et la barre des menus.",
  countDownWithMe: "Comptez avec moi", addToCalendar: "Ajouter au calendrier", appleOutlook: "Calendrier Apple ou Outlook",
  googleCalendar: "Google Agenda", downloadIcs: "Télécharger le .ics", addToWallet: "Ajouter à Apple Wallet", getTheApp: "Obtenir l’app",
  embedOnSite: "Intégrer à votre site", embedTitle: "Intégrer ce compte à rebours",
  embedBody: "Collez ceci là où le compte à rebours doit apparaître. Il défile en direct et suit les modifications de son créateur.",
  embedOptions: "Options : data-theme=\"dark\" ou \"light\" au lieu de son propre style, et data-end=\"recap\", \"countup\" ou \"hide\" pour ce qui s’affiche à zéro (ou data-message=\"Les portes sont ouvertes !\").",
  copy: "Copier", copied: "Copié", done: "Terminé",
  counted: { one: "{n} jour compté", other: "{n} jours comptés" },
  countedHours: { one: "{n} heure comptée", other: "{n} heures comptées" },
  ofUs: "Nous étions {n}", countedDown: "{n} ont fait le compte à rebours",
  notesInCoffin: { one: "{n} mot dans le cercueil", other: "{n} mots dans le cercueil" },
  guessedClosest: "{names} a vu le plus juste", together: "{n} ont fait le compte à rebours ensemble",
  coffinOpen: "🦇 Le cercueil est ouvert", coffinSealed: "🦇 Le cercueil scellé",
  coffinNothingLeft: "Personne n’a rien laissé cette fois.",
  coffinFromEveryone: { one: "{n} mot de tous ceux qui ont compté.", other: "{n} mots de tous ceux qui ont compté." },
  coffinWasSealed: { one: "{n} mot y était scellé. Tous ceux qui en ont laissé un, ou ont compté dans l’app, peuvent l’ouvrir.", other: "{n} mots y étaient scellés. Tous ceux qui en ont laissé un, ou ont compté dans l’app, peuvent l’ouvrir." },
  coffinNothingYet: "Rien de scellé pour l’instant.", coffinSoFar: "{n} scellés jusqu’ici.",
  coffinInvite: "Laissez un mot ou une photo. Personne ne le voit avant zéro, puis tout le monde le voit.",
  yourName: "Votre nom", yourNote: "Votre mot", addPhoto: "Ajouter une photo", addPhotos: "Ajouter jusqu’à {n} photos",
  changePhoto: "Changer la photo", changePhotos: "Changer les photos", photos: "{n} photos",
  sealing: "Scellement…", sealIt: "Sceller", whatYouSealed: "Ce que vous avez scellé", remove: "Retirer", report: "Signaler", reported: "Signalé", you: "(vous)",
  couldntSeal: "Impossible de sceller. Réessayez.", couldntReadPhoto: "Impossible de lire cette photo.", photoTooLarge: "Cette photo est trop lourde.",
  resultsIn: "Les résultats sont là", guessTheDate: "Pronostiquez la date",
  calledIt: "{names} a vu le plus juste. C’est arrivé le {date}.", happenedOn: "C’est arrivé le {date}.",
  guessingClosed: "Les pronostics sont clos. Le plus proche gagne une fois la vraie date connue.",
  guessPrompt: "Quand pensez-vous que ça arrivera ? Le pronostic le plus proche gagne le droit de s’en vanter.",
  yourGuess: "Votre pronostic", changeGuess: "Changer mon pronostic", lockIn: "Valider", noGuesses: "Pas encore de pronostic. Soyez le premier.",
  couldntSaveGuess: "Impossible d’enregistrer votre pronostic.", spotOn: "pile poil", offBy: "{span} d’écart",
  madeWith: "Créé avec", cantEmbed: "Ce compte à rebours ne peut pas être intégré.",
  daysLeft: { one: "{n} jour", other: "{n} jours" }, toGo: "restants", toGoOn: "jusqu’au {date}",
  sinceLower: "depuis le {date}", andCounting: "et ça continue",
  crypt: "La Crypte", cryptOf: "La Crypte : {name}", all: "Tous",
  cryptDescription: "Des comptes à rebours vers les fêtes, les éclipses, les solstices et les grands matchs. Comptez ensemble.",
  cryptPitch: "Sur l’écran verrouillé, la montre et la barre des menus.", getCountdowncula: "Obtenir Count Downcula",
  cryptEmpty: "Rien pour l’instant. Revenez bientôt.",
  holidays: "Fêtes", sky: "Ciel", sports: "Sport", fun: "Journées insolites",
  notFoundBody: "Le lien est peut-être erroné, ou son créateur l’a retiré.",
  cryptIntro: "Des comptes à rebours qui valent l’attente. Choisissez-en un pour compter avec tout le monde ; les fêtes arrivent à minuit, où que vous soyez.",
  notFoundTitle: "Ce compte à rebours s’est volatilisé",
  categoryTitle: "Comptes à rebours : {name}",
  counting: { one: "{n} compte", other: "{n} comptent" },
};

const DICTIONARIES: Record<Locale, Dictionary> = { en, ja, de, es, "pt-BR": ptBR, fr };

/** Text in `locale`, with {placeholders} filled in. A plural message picks its form from `n`. */
export function t(locale: Locale, key: Key, vars: Record<string, string | number> = {}): string {
  const message: Message = DICTIONARIES[locale][key] ?? en[key];
  const text = typeof message === "string"
    ? message
    : new Intl.PluralRules(locale).select(Number(vars.n ?? 0)) === "one" ? message.one : message.other;
  return text.replace(/\{(\w+)\}/g, (_, name: string) => {
    const value = vars[name];
    if (value === undefined) return `{${name}}`;
    return typeof value === "number" ? value.toLocaleString(locale) : value;
  });
}

/** "Ana, Ben and Cy" in the viewer's language. */
export function listOf(locale: Locale, names: string[]): string {
  return new Intl.ListFormat(locale, { type: "conjunction" }).format(names);
}
