LOADFLOW — SISTEMA DE CARREGAMENTO

Este pacote foi feito para funcionar ao lado do DockFlow atual, usando o MESMO projeto Supabase e os MESMOS usuários administradores. Ele cria tabelas e funções com prefixo loading_, então não mexe nos dados atuais.

FUNCIONALIDADES
- 4 docas de carregamento
- Check-in por QR Code
- Nome e sobrenome do motorista
- Placa do veículo
- Número da Load
- Ordem de chegada
- Chamada para uma doca
- Notificação no celular mesmo com o site minimizado
- Horário de chegada
- Horário de saída
- Tempo total de permanência
- Permanência média do dia
- Alerta para o administrador quando chega novo motorista

INSTALAÇÃO RESUMIDA
1. No GitHub, crie um NOVO repositório público chamado loadflow.
2. Envie os arquivos index.html, styles.css, app.js, config.js, service-worker.js, manifest.webmanifest, icon-192.png e icon-512.png.
3. Ative GitHub Pages: Settings > Pages > Deploy from a branch > main > /(root).
4. No MESMO Supabase do DockFlow, abra SQL Editor, cole todo o conteúdo de setup-loadflow.sql e clique Run.
5. Em Edge Functions, crie uma função chamada notify-loading-driver, cole o arquivo supabase/functions/notify-loading-driver/index.ts e faça Deploy.
6. Na função, deixe Verify JWT with legacy secret DESLIGADO.
7. Não precisa criar novos Secrets: ela reutiliza VAPID_PRIVATE_KEY e VAPID_SUBJECT que já existem no seu projeto.
8. O mesmo usuário admin do DockFlow funcionará aqui.

LINKS APÓS PUBLICAR
Motorista: https://leonardozanella23-droid.github.io/loadflow/
Administrador: https://leonardozanella23-droid.github.io/loadflow/?admin=1

IMPORTANTE
Não envie nenhum arquivo de chave privada para o GitHub.
