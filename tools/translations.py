#!/usr/bin/env python3
"""Usage Pace 번역 원본 (source of truth).
문자열을 추가·수정하면 여기서 고친 뒤 실행:  python3 tools/translations.py Resources
Generates Resources/<lang>.lproj/Localizable.strings.
Column order: en, ko, ja, zh-Hans, zh-Hant, es, fr, de, pt-BR
Strings with format args use printf rules (%@, %d, %1$@, %% for a literal %).
"""
import os, sys

LANGS = ["en", "ko", "ja", "zh-Hans", "zh-Hant", "es", "fr", "de", "pt-BR"]

T = [
# ---- General ----
("app.settings", "Settings", "설정", "設定", "设置", "設定", "Ajustes", "Réglages", "Einstellungen", "Ajustes"),
("button.refresh", "Refresh", "새로고침", "更新", "刷新", "重新整理", "Actualizar", "Actualiser", "Aktualisieren", "Atualizar"),
("button.quit", "Quit", "종료", "終了", "退出", "結束", "Salir", "Quitter", "Beenden", "Sair"),
("button.done", "Done", "완료", "完了", "完成", "完成", "Listo", "OK", "Fertig", "OK"),
("button.connect", "Connect", "연결하기", "接続", "连接", "連線", "Conectar", "Connecter", "Verbinden", "Conectar"),
("button.disconnect", "Disconnect", "연결 해제", "接続解除", "断开连接", "中斷連線", "Desconectar", "Déconnecter", "Trennen", "Desconectar"),

# ---- Cards ----
("card.session", "Current session", "현재 세션", "現在のセッション", "当前会话", "目前工作階段",
 "Sesión actual", "Session en cours", "Aktuelle Sitzung", "Sessão atual"),
("card.weekly.all", "Weekly · All models", "주간 한도 · 전체 모델", "週間上限 · 全モデル", "每周限额 · 所有模型", "每週限額 · 所有模型",
 "Semanal · Todos los modelos", "Hebdo · Tous les modèles", "Woche · Alle Modelle", "Semanal · Todos os modelos"),
("meter.used", "Used", "사용량", "使用量", "已用", "已用", "Usado", "Utilisé", "Genutzt", "Usado"),
("meter.elapsed", "Elapsed", "시간 경과", "経過", "已过时间", "已過時間", "Tiempo", "Temps", "Zeit", "Tempo"),
("meter.marker.help", "Time elapsed so far", "지금까지 흐른 시간 위치", "現在までの経過時間", "目前已过的时间", "目前已過的時間",
 "Tiempo transcurrido hasta ahora", "Temps écoulé jusqu'ici", "Bisher verstrichene Zeit", "Tempo decorrido até agora"),
# %1$@ elapsed, %2$@ window length, %3$@ remaining, %4$@ reset date
("card.timeline",
 "%1$@ of %2$@ elapsed · resets in %3$@ (%4$@)",
 "%2$@ 중 %1$@ 경과 · 리셋까지 %3$@ (%4$@)",
 "%2$@中 %1$@経過 · リセットまで%3$@（%4$@）",
 "%2$@ 中已过 %1$@ · %3$@ 后重置（%4$@）",
 "%2$@ 中已過 %1$@ · %3$@ 後重置（%4$@）",
 "%1$@ de %2$@ transcurridos · se reinicia en %3$@ (%4$@)",
 "%1$@ écoulés sur %2$@ · réinitialisation dans %3$@ (%4$@)",
 "%1$@ von %2$@ vergangen · Reset in %3$@ (%4$@)",
 "%1$@ de %2$@ decorridos · reinicia em %3$@ (%4$@)"),
("card.weekly.notStarted",
 "The weekly window hasn't started yet", "아직 주간 창이 시작되지 않았어요", "週間ウィンドウはまだ始まっていません",
 "每周周期尚未开始", "每週週期尚未開始", "La ventana semanal aún no ha comenzado",
 "La période hebdomadaire n'a pas encore commencé", "Das Wochenfenster hat noch nicht begonnen", "A janela semanal ainda não começou"),
("card.session.notStarted",
 "No active session · the 5-hour window starts with your first message",
 "세션 시작 전 · 첫 메시지부터 5시간 창이 시작돼요",
 "セッション開始前 · 最初のメッセージから5時間のウィンドウが始まります",
 "会话未开始 · 5 小时周期从第一条消息开始",
 "工作階段未開始 · 5 小時週期從第一則訊息開始",
 "Sin sesión activa · la ventana de 5 horas empieza con tu primer mensaje",
 "Aucune session active · la fenêtre de 5 heures démarre à votre premier message",
 "Keine aktive Sitzung · das 5-Stunden-Fenster beginnt mit deiner ersten Nachricht",
 "Nenhuma sessão ativa · a janela de 5 horas começa com sua primeira mensagem"),
("card.projection.hit",
 "At this pace, you'll hit the limit around %@",
 "이 속도면 %@쯤 한도 도달 예상",
 "このペースだと%@頃に上限に達する見込み",
 "按此速度，预计在 %@ 左右达到上限",
 "照此速度，預計在 %@ 左右達到上限",
 "A este ritmo, alcanzarás el límite hacia %@",
 "À ce rythme, vous atteindrez la limite vers %@",
 "Bei diesem Tempo erreichst du das Limit gegen %@",
 "Nesse ritmo, você atingirá o limite por volta de %@"),
("card.projection.end",
 "At this pace, about %@ used by reset",
 "이 속도면 리셋 시점에 약 %@ 사용 예상",
 "このペースだとリセット時に約%@使用の見込み",
 "按此速度，重置时预计用掉约 %@",
 "照此速度，重置時預計用掉約 %@",
 "A este ritmo, usarás cerca del %@ al reiniciarse",
 "À ce rythme, environ %@ utilisés à la réinitialisation",
 "Bei diesem Tempo ca. %@ verbraucht bis zum Reset",
 "Nesse ritmo, cerca de %@ usados até reiniciar"),

# ---- Pace badge (percentage points) ----
("pace.under", "%d pts to spare", "여유 %d%%p", "余裕 %dpt", "富余 %d 点", "餘裕 %d 點",
 "Margen %d pts", "Marge %d pts", "Puffer %d Pkt.", "Folga %d p.p."),
("pace.on", "On pace", "적정 페이스", "適正ペース", "节奏正常", "節奏正常", "Buen ritmo", "Bon rythme", "Im Plan", "No ritmo"),
("pace.fast", "Fast +%d pts", "빠름 +%d%%p", "やや速い +%dpt", "偏快 +%d 点", "偏快 +%d 點",
 "Rápido +%d pts", "Rapide +%d pts", "Schnell +%d Pkt.", "Rápido +%d p.p."),
("pace.over", "Too fast +%d pts", "과속 +%d%%p", "速すぎ +%dpt", "过快 +%d 点", "過快 +%d 點",
 "Muy rápido +%d pts", "Trop rapide +%d pts", "Zu schnell +%d Pkt.", "Rápido demais +%d p.p."),

# ---- Footer ----
("footer.updated", "Updated %1$@ · %2$@", "업데이트 %1$@ · %2$@", "更新 %1$@ · %2$@", "更新于 %1$@ · %2$@", "更新於 %1$@ · %2$@",
 "Actualizado %1$@ · %2$@", "Mis à jour %1$@ · %2$@", "Aktualisiert %1$@ · %2$@", "Atualizado %1$@ · %2$@"),

("footer.source",
 "Updates when Claude Code responds in the terminal",
 "터미널 Claude Code 응답 때마다 갱신",
 "ターミナルの Claude Code の応答ごとに更新",
 "终端中的 Claude Code 每次回复时更新",
 "終端機中的 Claude Code 每次回覆時更新",
 "Se actualiza con cada respuesta de Claude Code en la terminal",
 "Mis à jour à chaque réponse de Claude Code dans le Terminal",
 "Aktualisiert bei jeder Antwort von Claude Code im Terminal",
 "Atualiza a cada resposta do Claude Code no Terminal"),
("stale.notice",
 "Last updated %@. Use Claude Code in the terminal to refresh.",
 "%@ 데이터예요. 터미널에서 Claude Code를 쓰면 갱신돼요.",
 "%@のデータです。ターミナルで Claude Code を使うと更新されます。",
 "这是%@的数据。在终端使用 Claude Code 即可更新。",
 "這是%@的資料。在終端機使用 Claude Code 即可更新。",
 "Última actualización: %@. Usa Claude Code en la terminal para actualizar.",
 "Dernière mise à jour : %@. Utilisez Claude Code dans le Terminal pour actualiser.",
 "Stand: %@. Nutze Claude Code im Terminal, um zu aktualisieren.",
 "Última atualização: %@. Use o Claude Code no Terminal para atualizar."),
("empty.connect", "Connect Claude Code to see your usage.", "사용량을 보려면 Claude Code에 연결하세요.",
 "使用量を表示するには Claude Code に接続してください。", "连接 Claude Code 以查看用量。", "連線 Claude Code 以查看用量。",
 "Conecta Claude Code para ver tu uso.", "Connectez Claude Code pour voir votre utilisation.",
 "Verbinde Claude Code, um deine Nutzung zu sehen.", "Conecte o Claude Code para ver seu uso."),
("empty.waiting",
 "Connected. Send a message in Claude Code in your terminal and your usage will appear here.",
 "연결됐어요. 터미널의 Claude Code에서 메시지를 한 번 보내면 여기에 사용량이 표시돼요.",
 "接続しました。ターミナルの Claude Code でメッセージを送ると、ここに使用量が表示されます。",
 "已连接。在终端的 Claude Code 中发送一条消息后，用量会显示在这里。",
 "已連線。在終端機的 Claude Code 中傳送一則訊息後，用量會顯示在這裡。",
 "Conectado. Envía un mensaje en Claude Code desde la terminal y tu uso aparecerá aquí.",
 "Connecté. Envoyez un message dans Claude Code depuis le Terminal et votre utilisation s'affichera ici.",
 "Verbunden. Sende im Terminal eine Nachricht in Claude Code, dann erscheint deine Nutzung hier.",
 "Conectado. Envie uma mensagem no Claude Code pelo Terminal e seu uso aparecerá aqui."),
# ---- Settings ----
("settings.language", "Language", "언어 · Language", "言語 · Language", "语言 · Language", "語言 · Language",
 "Idioma · Language", "Langue · Language", "Sprache · Language", "Idioma · Language"),
("language.system", "System default", "시스템 설정 따름", "システム設定に従う", "跟随系统", "跟隨系統",
 "Predeterminado del sistema", "Langue du système", "Systemstandard", "Padrão do sistema"),
("settings.connected", "Connected", "연결됨", "接続済み", "已连接", "已連線", "Conectado", "Connecté", "Verbunden", "Conectado"),
("settings.cc", "Claude Code connection", "Claude Code 연결", "Claude Code 連携", "Claude Code 连接", "Claude Code 連線",
 "Conexión con Claude Code", "Connexion à Claude Code", "Claude-Code-Verbindung", "Conexão com o Claude Code"),
("settings.cc.hint",
 "Reads usage from the status line of Claude Code in the terminal, without using any login or credentials. Numbers update each time it responds; usage in the desktop app or on the web shows up on the next terminal response. Any status line you already use keeps working.",
 "터미널 Claude Code의 상태 표시줄에서 사용량을 받아와요. 로그인 정보는 쓰지 않아요. 응답할 때마다 갱신되고, 데스크톱 앱·웹에서 쓴 양은 다음 터미널 응답 때 반영돼요. 기존 상태 표시줄 설정은 그대로 유지돼요.",
 "ターミナルの Claude Code のステータスラインから使用量を取得します。ログイン情報は使いません。応答のたびに更新され、デスクトップアプリや Web での使用分は次のターミナルでの応答時に反映されます。既存のステータスラインもそのまま動作します。",
 "从终端中 Claude Code 的状态栏读取用量，不使用任何登录信息。每次回复时更新；在桌面应用或网页上的用量会在下一次终端回复时反映。现有的状态栏设置会继续生效。",
 "從終端機中 Claude Code 的狀態列讀取用量，不使用任何登入資訊。每次回覆時更新；在桌面應用程式或網頁上的用量會在下一次終端機回覆時反映。現有的狀態列設定會繼續運作。",
 "Lee el uso desde la línea de estado de Claude Code en la terminal, sin usar inicios de sesión ni credenciales. Se actualiza con cada respuesta; el uso en la app de escritorio o la web se refleja en la siguiente respuesta de la terminal. Tu línea de estado actual sigue funcionando.",
 "Lit l'utilisation depuis la ligne d'état de Claude Code dans le Terminal, sans aucun identifiant. Mise à jour à chaque réponse ; l'utilisation dans l'app de bureau ou sur le web apparaît à la prochaine réponse dans le Terminal. Votre ligne d'état actuelle continue de fonctionner.",
 "Liest die Nutzung aus der Statuszeile von Claude Code im Terminal, ganz ohne Anmeldedaten. Aktualisiert sich bei jeder Antwort; Nutzung in der Desktop-App oder im Web erscheint bei der nächsten Antwort im Terminal. Deine bestehende Statuszeile funktioniert weiter.",
 "Lê o uso pela linha de status do Claude Code no Terminal, sem usar login nem credenciais. Atualiza a cada resposta; o uso no app para desktop ou na web aparece na próxima resposta no Terminal. Sua linha de status atual continua funcionando."),
("settings.menubar", "Menu bar (used % / elapsed %)", "메뉴바 표시 (사용% / 경과%)", "メニューバー（使用% / 経過%）",
 "菜单栏（已用% / 已过%）", "選單列（已用% / 已過%）", "Barra de menús (usado % / tiempo %)",
 "Barre des menus (utilisé % / écoulé %)", "Menüleiste (genutzt % / verstrichen %)", "Barra de menus (usado % / decorrido %)"),
("about.disclaimer",
 "Independent app. Not affiliated with or endorsed by Anthropic.",
 "독립 개발 앱이며 Anthropic과 관련이 없어요.",
 "独立したアプリであり、Anthropic とは提携・承認関係にありません。",
 "独立应用，与 Anthropic 无关联，也未获其认可。",
 "獨立應用程式，與 Anthropic 無關聯，也未獲其認可。",
 "App independiente. Sin afiliación ni respaldo de Anthropic.",
 "App indépendante, sans affiliation ni approbation d'Anthropic.",
 "Unabhängige App. Nicht mit Anthropic verbunden oder von Anthropic unterstützt.",
 "App independente. Sem afiliação ou endosso da Anthropic."),
("window.weekly", "Weekly", "주간", "週間", "每周", "每週", "Semanal", "Semaine", "Woche", "Semanal"),
("window.session", "Session", "세션", "セッション", "会话", "工作階段", "Sesión", "Session", "Sitzung", "Sessão"),
("settings.general", "General", "기타", "一般", "通用", "一般", "General", "Général", "Allgemein", "Geral"),
("settings.launchAtLogin", "Launch at login", "로그인 시 자동 실행", "ログイン時に起動", "登录时启动", "登入時啟動",
 "Abrir al iniciar sesión", "Ouvrir à l'ouverture de session", "Beim Anmelden starten", "Abrir ao iniciar sessão"),

# ---- Errors ----
("error.settingsUnreadable",
 "Couldn't read ~/.claude/settings.json, so nothing was changed. Check that the file is valid JSON.",
 "~/.claude/settings.json을 읽지 못해서 아무것도 바꾸지 않았어요. 파일이 올바른 JSON인지 확인하세요.",
 "~/.claude/settings.json を読み取れなかったため、何も変更していません。ファイルが正しい JSON か確認してください。",
 "无法读取 ~/.claude/settings.json，因此未做任何更改。请检查该文件是否为有效的 JSON。",
 "無法讀取 ~/.claude/settings.json，因此未做任何變更。請確認該檔案是有效的 JSON。",
 "No se pudo leer ~/.claude/settings.json, así que no se cambió nada. Comprueba que el archivo sea JSON válido.",
 "Impossible de lire ~/.claude/settings.json : rien n'a été modifié. Vérifiez que le fichier est un JSON valide.",
 "~/.claude/settings.json konnte nicht gelesen werden, daher wurde nichts geändert. Prüfe, ob die Datei gültiges JSON ist.",
 "Não foi possível ler ~/.claude/settings.json, então nada foi alterado. Verifique se o arquivo é um JSON válido."),
("error.settingsWrite", "Couldn't update Claude Code settings (%@).", "Claude Code 설정을 바꾸지 못했어요 (%@).",
 "Claude Code の設定を更新できませんでした（%@）。", "无法更新 Claude Code 设置（%@）。", "無法更新 Claude Code 設定（%@）。",
 "No se pudo actualizar la configuración de Claude Code (%@).", "Impossible de mettre à jour les réglages de Claude Code (%@).",
 "Claude-Code-Einstellungen konnten nicht aktualisiert werden (%@).", "Não foi possível atualizar as configurações do Claude Code (%@)."),
("error.parse", "Couldn't read the saved usage data.", "저장된 사용량 데이터를 읽지 못했어요.", "保存された使用量データを読み取れませんでした。",
 "无法读取已保存的用量数据。", "無法讀取已儲存的用量資料。", "No se pudieron leer los datos de uso guardados.",
 "Impossible de lire les données d'utilisation enregistrées.", "Gespeicherte Nutzungsdaten konnten nicht gelesen werden.",
 "Não foi possível ler os dados de uso salvos."),

]


def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def main(out_root):
    keys = [row[0] for row in T]
    assert len(keys) == len(set(keys)), "duplicate keys"
    for row in T:
        assert len(row) == 1 + len(LANGS), f"wrong column count: {row[0]}"
    for i, lang in enumerate(LANGS):
        d = os.path.join(out_root, f"{lang}.lproj")
        os.makedirs(d, exist_ok=True)
        lines = [f"/* Usage Pace — {lang}. Format args follow printf rules (%@, %d, %1$@; %% = literal %). */", ""]
        for row in T:
            lines.append(f'"{row[0]}" = "{esc(row[1 + i])}";')
        with open(os.path.join(d, "Localizable.strings"), "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
    print(f"{len(T)} keys × {len(LANGS)} languages → {out_root}")


if __name__ == "__main__":
    main(sys.argv[1])
