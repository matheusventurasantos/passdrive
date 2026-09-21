import 'appearance_preferences.dart';

String tr(String source) => AppearancePreferences.instance.language == 'en'
    ? english[source] ?? source
    : source;

bool get isEnglish => AppearancePreferences.instance.language == 'en';

String tx(String portuguese, String translated) =>
    isEnglish ? translated : portuguese;

final Map<String, String> english = Map.fromEntries(
  _catalog.trim().split('\n').map((line) {
    final separator = line.indexOf('|');
    return MapEntry(
      line.substring(0, separator),
      line.substring(separator + 1),
    );
  }),
);

const _catalog = r'''
1 dia|1 day
1 hora|1 hour
12 serviços|12 services
15 minutos|15 minutes
22 senhas comprometidas|22 compromised passwords
3 serviços|3 services
30 dias|30 days
7 dias|7 days
8 serviços|8 services
A URL do cofre é inválida.|The vault URL is invalid.
A alteração foi cancelada.|The change was canceled.
A atualização não passou na validação de segurança.|The update failed the security check.
A chave do cofre será mantida. Apenas a proteção da senha será atualizada.|The vault key will remain unchanged. Only its password protection will be updated.
A conclusão continua no celular. Você pode seguir usando o computador.|Finish on your phone. You can keep using your computer.
A conexão foi bloqueada, mas não foi possível salvar a revogação local.|The connection was blocked, but the local revocation could not be saved.
A conexão foi encerrada pelo celular. Faça um novo pareamento.|The phone ended the connection. Pair again.
A conexão foi encerrada.|The connection was closed.
A confirmação da nova senha não confere.|The new passwords do not match.
A estrutura do cofre é inválida.|The vault structure is invalid.
A leitura pelo app autoriza o computador por 1 hora.|Scanning with the app authorizes the computer for 1 hour.
A senha atual está incorreta.|The current password is incorrect.
A senha mestra está incorreta.|The master password is incorrect.
A senha mestra não pôde desbloquear o cofre.|The master password could not unlock the vault.
A senha não desbloqueou seu cofre. Confira e tente novamente.|The password did not unlock your vault. Check it and try again.
A verificação de segurança do cofre é inválida.|The vault security check is invalid.
A versão do cofre é inválida.|The vault version is invalid.
Abra Sincronização e dispositivos nos ajustes do PassDrive. Os dois aparelhos precisam estar na mesma rede.|Open Sync and devices in PassDrive settings. Both devices must be on the same network.
Abrir cofre|Open vault
Acesse a aba ajustes > Sincronização > Ler QR CODE|Open Settings > Sync > Scan QR CODE
Acesso ao cofre|Vault access
Adicionar|Add
Adicionar aos favoritos|Add to favorites
Adicionar conta|Add account
Adicionar serviço|Add service
Adicione senhas ao seu cofre|Add passwords to your vault
Adicione um acesso para guardar suas credenciais com segurança.|Add a login to store your credentials securely.
Adicione um email principal para encontrar seus serviços com mais facilidade.|Add a primary email to find your services more easily.
Agora não|Not now
Aguardando o celular autorizado na rede|Waiting for the authorized phone on the network
Aguardando sincronização|Waiting to sync
Ajustes|Settings
Alterar favorito da conta|Change account favorite
Alterar favorito do serviço|Change service favorite
Alterar senha mestra|Change master password
Altere suas senhas para manter suas contas seguras.|Update your passwords to keep your accounts secure.
Aparência e idioma|Appearance and language
Aplicar|Apply
Aponte a câmera para o QR CODE exibido|Point the camera at the QR CODE
Aponte para o QR Code exibido pelo PassDrive no computador.|Point at the QR code shown by PassDrive on your computer.
Após 1 minuto|After 1 minute
Após 15 minutos|After 15 minutes
Após 30 segundos|After 30 seconds
Após 5 minutos|After 5 minutes
Armazenado neste computador|Stored on this computer
Arquivo de chave-mestra inválido.|Invalid master key file.
Arquivo de desbloqueio|Unlock file
As senhas são diferentes.|The passwords do not match.
Atenção|Warning
Ative pelo menos um tipo de caractere para gerar.|Enable at least one character type to generate a password.
Atualizados recentemente|Recently updated
Atualização pronta. Reiniciando...|Update ready. Restarting...
Atualização disponível|Update available
Atualização de segurança disponível|Security update available
Atualização pronta|Update ready
Atualizar agora|Update now
A atualização foi baixada. Reinicie o app para concluir a instalação.|The update was downloaded. Restart the app to finish installing it.
Baixando atualização em segundo plano…|Downloading the update in the background…
Baixar atualização|Download update
Atualize suas senhas para proteger melhor suas contas.|Update your passwords to better protect your accounts.
Autorizar ao ler QR Code|Authorize when scanning a QR code
Autorizar computador|Authorize computer
Autorizar conexão|Authorize connection
Autorizar sem prazo?|Authorize without expiration?
Autorização expirada ou revogada.|Authorization expired or revoked.
Autorização expirada.|Authorization expired.
Backup criptografado salvo no local escolhido.|Encrypted backup saved to the selected location.
Backup e recuperação|Backup and recovery
Backup inválido ou de outro cofre.|Invalid backup or backup from another vault.
Backup restaurado|Backup restored
Backup restaurado com sucesso.|Backup restored successfully.
Baixar chave|Download key
Baixar chave-mestra|Download master key
Baixe sua chave-mestra|Download your master key
Biometria indisponível agora. Use sua senha ou chave-mestra.|Biometrics are unavailable right now. Use your password or master key.
Biometria indisponível neste aparelho.|Biometrics are unavailable on this device.
Biometria não ativada. Você pode continuar com sua senha e tentar novamente.|Biometrics were not enabled. Continue with your password and try again later.
Bloquear cofre|Lock vault
Bloquear o cofre encerra as autorizações. “Para sempre” não impede bloqueio ou revogação.|Locking the vault ends authorizations. “Forever” does not prevent locking or revocation.
Bloquear ao perder o foco|Lock when losing focus
Bloqueio automático|Auto-lock
Boa|Good
Buscar contas ou serviços|Search accounts or services
Cadastre um email principal para vincular serviços.|Add a primary email to link services.
Cancelar|Cancel
Celular|Phone
Celular desconectado. Aguardando reconexão na rede local.|Phone disconnected. Waiting to reconnect on the local network.
Celular desconectado. Aguardando reconexão.|Phone disconnected. Waiting to reconnect.
Chave-mestra salva no local escolhido.|Master key saved to the selected location.
Cofre|Vault
Cofre bloqueado.|Vault locked.
Cofre bloqueado. Sincronize novamente.|Vault locked. Sync again.
Cofre local criptografado|Encrypted local vault
Comprometidas|Compromised
Computador|Computer
Conclua a solicitação atual no celular.|Finish the current request on your phone.
Concluído|Done
Conectado|Connected
Conectar ao celular|Connect to phone
Conectar outro dispositivo|Connect another device
Conexão encerrada.|Connection closed.
Conexão indisponível.|Connection unavailable.
Conexão local criptografada|Encrypted local connection
Conexão não autorizada.|Connection not authorized.
Confiar neste computador|Trust this computer
Conexões encerradas. Não foi possível salvar a revogação.|Connections closed. Could not save the revocation.
Configuração de conexão incompatível.|Incompatible connection configuration.
Confira a conexão e tente novamente.|Check your connection and try again.
Confira a rede local e tente novamente.|Check your local network and try again.
Confirmar|Confirm
Confirmar identidade|Confirm identity
Confirmar nova senha|Confirm new password
Confirmar senha|Confirm password
Confirme a senha do aplicativo.|Confirm the app password.
Confirme e configure o dispositivo|Confirm and configure the device
Confirme sua senha ou chave-mestra para bloquear capturas de tela.|Confirm your password or master key to block screenshots.
Conta|Account
Conta vinculada|Linked account
Conta vinculada (opcional)|Linked account (optional)
Contas|Accounts
Contato|Contact
Continuar|Continue
Continuar no celular|Continue on phone
Continue pelo celular para autorizar e preencher os dados.|Continue on your phone to authorize and enter the details.
Controle o que pode ser visto e compartilhado|Control what can be seen and shared
Copiar senha|Copy password
Credencial|Credential
Criados recentemente|Recently created
Crie seu cofre seguro|Create your secure vault
Crie uma nova senha mestra|Create a new master password
Crie uma senha forte e ative a biometria para mais segurança.|Create a strong password and enable biometrics for additional security.
Código do computador|Computer code
Código expirado. Gere uma nova conexão no computador.|Code expired. Start a new connection on the computer.
Código incorreto ou conexão não autorizada.|Incorrect code or unauthorized connection.
Código-fonte|Source code
Desative para impedir capturas e visualização recente.|Turn off to prevent screenshots and recent-app previews.
Desbloquear com biometria|Unlock with biometrics
Desbloqueie o cofre no celular para retomar a conexão. Nenhuma senha fica salva neste computador.|Unlock the vault on your phone to reconnect. Passwords are not saved on this computer.
Desconectado|Disconnected
Desconectar dispositivo?|Disconnect device?
Desfazer|Undo
Depois|Later
Detectar dispositivo|Find device
Dicas de segurança|Security tips
Digite a senha atual|Enter current password
Digite a senha do aplicativo.|Enter the app password.
Digite este código no celular|Enter this code on your phone
Digite no celular o código abaixo:|Enter the following code on your phone:
Digite os 3 caracteres exibidos no computador.|Enter the 3 characters shown on your computer.
Digite ou selecione um email|Enter or select an email
Digite sua senha|Enter your password
Digite sua senha atual.|Enter your current password.
Digite sua senha mestra para continuar.|Enter your master password to continue.
Digite sua senha para continuar.|Enter your password to continue.
Digite um email válido ou deixe em branco.|Enter a valid email or leave blank.
Digite um email válido.|Enter a valid email.
Digite uma senha forte|Enter a strong password
Digite uma senha ou gere uma senha forte.|Enter a password or generate a strong one.
Dispositivo|Device
Dispositivo conectado|Connected device
Dispositivo desconectado.|Device disconnected.
Dispositivo encontrado|Device found
Dispositivo não autorizado.|Device not authorized.
Dispositivos|Devices
Download cancelado. Você pode tentar novamente.|Download canceled. You can try again.
Editar|Edit
Editar conta|Edit account
Editar serviço|Edit service
Email principal|Primary email
Encontre o celular na rede e confirme o código por lá.|Find your phone on the network and confirm the code there.
Endereço|Address
Entendi|Got it
Entrar|Sign in
Entrar com biometria|Sign in with biometrics
Entrar com chave-mestra|Sign in with master key
Entre com senha ou arquivo e ative a biometria novamente nos Ajustes.|Sign in with your password or key file and enable biometrics again in Settings.
Erro de conexão|Connection error
Escaneie o QR Code|Scan the QR code
Escolha uma senha menos comum e previsível.|Choose a less common and predictable password.
Escolher duração|Choose duration
Essa conta será removida do cofre.|This account will be removed from the vault.
Essa credencial será removida do cofre.|This credential will be removed from the vault.
Essas senhas apareceram em vazamentos conhecidos e devem ser alteradas.|These passwords appeared in known data breaches and should be changed.
Esta chave não abre seu cofre. Selecione o arquivo correspondente.|This key does not open your vault. Select the matching file.
Esta chave não pertence a este cofre.|This key does not belong to this vault.
Esta conta ainda não tem serviços|This account has no services yet
Esta conta já está cadastrada.|This account already exists.
Esta conta possui serviços vinculados. Remova ou transfira esses serviços antes de excluir.|This account has linked services. Remove or transfer them before deleting the account.
Este arquivo abre seu cofre sem a senha. Guarde-o em um local seguro e não compartilhe. Ele não contém um backup das suas senhas.|This file opens your vault without the password. Keep it safe and do not share it. It does not contain a backup of your passwords.
Este arquivo abre seu cofre sem a senha. Guarde-o em um local seguro e não o compartilhe.|This file opens your vault without the password. Keep it safe and do not share it.
Este arquivo abre seu cofre. Guarde em local seguro. Não é um backup das senhas.|This file opens your vault. Keep it safe. It is not a password backup.
Este arquivo não é uma chave-mestra válida do PassDrive.|This file is not a valid PassDrive master key.
Este computador poderá reconectar até você bloquear o cofre ou revogar o acesso.|This computer can reconnect until you lock the vault or revoke access.
Encerra a sessão deste computador ao trocar para outro app ou janela.|Ends this computer session when switching to another app or window.
Este dispositivo poderá exibir e copiar as senhas enquanto o celular estiver conectado e desbloqueado.|This device can display and copy passwords while the phone is connected and unlocked.
Este email será registrado como uma nova conta.|This email will be added as a new account.
Estrutura do cofre inválida.|Invalid vault structure.
Evitar caracteres semelhantes|Avoid similar characters
Evite datas, telefones e sequências numéricas previsíveis.|Avoid dates, phone numbers and predictable number sequences.
Evite repetir o mesmo caractere.|Avoid repeating the same character.
Evite sequências previsíveis de caracteres.|Avoid predictable character sequences.
Excluir|Delete
Excluir conta|Delete account
Excluir conta?|Delete account?
Excluir serviço|Delete service
Excluir serviço?|Delete service?
Exibir senha|Show password
Existem senhas comprometidas|Some passwords are compromised
Existem senhas fracas|Some passwords are weak
Expira em 2 minutos. Cada código aceita até 3 tentativas.|Expires in 2 minutes. Each code allows up to 3 attempts.
Exportar backup|Export backup
Favoritos primeiro|Favorites first
Fechar|Close
Fechar aviso|Dismiss warning
Fechar janela|Close window
Fraca|Weak
Fracas|Weak
Gerador|Generator
Gerador de senhas|Password generator
Gerar outra senha|Generate another password
Gerencie conexões e aparelhos vinculados|Manage connections and linked devices
GitHub, Netflix ou PayPal|GitHub, Netflix or PayPal
Guarde o acesso de um site ou aplicativo.|Store a website or app login.
Guarde suas senhas com segurança no dispositivo.|Store your passwords securely on your device.
Guarde suas senhas com segurança no dispositivo. Sincronize quando quiser.|Store your passwords securely on your device. Sync whenever you want.
Identidade do cofre inválida.|Invalid vault identity.
Imediatamente|Immediately
Importe, exporte e recupere seu cofre|Import, export and recover your vault
Informe um endereço válido, como github.com.|Enter a valid address, such as github.com.
Início|Home
Ler QR Code|Scan QR code
Ler QR Code do computador|Scan computer QR code
Letras maiúsculas|Uppercase letters
Letras maiúsculas (A–Z)|Uppercase letters (A–Z)
Letras minúsculas|Lowercase letters
Letras minúsculas (a–z)|Lowercase letters (a–z)
Limitador ainda não foi carregado.|Attempt limiter has not loaded yet.
Limite de mensagens de sincronização excedido.|Sync message limit exceeded.
Limite de solicitações atingido.|Request limit reached.
Limpa em 1 minuto.|Cleared after 1 minute.
Limpa em 30 segundos.|Cleared after 30 seconds.
Limpar busca|Clear search
Limpar filtro|Clear filter
Limpar área de transferência|Clear clipboard
MEU COFRE|MY VAULT
Mais opções|More options
Mantém uma notificação ativa. Não funciona se o Android forçar a parada do app.|Keeps a notification active. Does not work if Android force-stops the app.
Maximizar|Maximize
Mensagem de conexão inválida.|Invalid connection message.
Mensagem de sincronização inválida.|Invalid sync message.
Mensagem inválida.|Invalid message.
Mensagem repetida ou fora de ordem.|Duplicate or out-of-order message.
Metadados do cofre inválidos.|Invalid vault metadata.
Minhas senhas|My passwords
Minimizar|Minimize
Mostrar senha|Show password
Mostrar somente favoritos|Show favorites only
Mostrar todos os serviços|Show all services
Nenhum computador autorizado.|No authorized computers.
Nenhum dispositivo conectado|No device connected
Nenhum dispositivo encontrado|No device found
Nenhum dispositivo encontrado. Verifique a rede local.|No device found. Check the local network.
Nenhum resultado encontrado|No results found
Nenhuma conta adicionada|No accounts added
Nenhuma conta encontrada.|No accounts found.
Nome (A–Z)|Name (A–Z)
Nome do serviço (opcional)|Service name (optional)
Nome para organização (opcional)|Organization name (optional)
Nova senha|New password
Nunca|Never
Não conseguimos acessar o arquivo. Selecione-o novamente.|Could not access the file. Select it again.
Não conseguimos concluir. Tente novamente; seu cofre não será apagado.|Could not finish. Try again; your vault will not be deleted.
Não foi possível abrir este endereço.|Could not open this address.
Não foi possível abrir o cofre local.|Could not open the local vault.
Não foi possível acessar o cofre.|Could not access the vault.
Não foi possível atualizar a proteção de captura de tela.|Could not update screenshot protection.
Não foi possível autorizar esta conexão.|Could not authorize this connection.
Não foi possível autorizar. Confira o código, a rede e o prazo de 2 minutos. Após 3 tentativas, gere outro código no computador.|Could not authorize. Check the code, network and 2-minute limit. After 3 attempts, generate another code on your computer.
Não foi possível baixar a atualização.|Could not download the update.
Não foi possível concluir a leitura da chave-mestra.|Could not finish reading the master key.
Não foi possível concluir esta operação.|Could not complete this operation.
Não foi possível concluir no celular.|Could not finish on the phone.
Não foi possível concluir. Confira a biometria do aparelho ou tente novamente.|Could not finish. Check your device biometrics or try again.
Não foi possível concluir. Tente novamente.|Could not finish. Try again.
Não foi possível confirmar sua biometria.|Could not confirm your biometrics.
Não foi possível consultar a base.|Could not query the database.
Não foi possível iniciar as conexões locais.|Could not start local connections.
Não foi possível iniciar a atualização.|Could not start the update.
Não foi possível ler a chave-mestra.|Could not read the master key.
Não foi possível ler o cofre. Feche o app e tente novamente.|Could not read the vault. Close the app and try again.
Não foi possível preparar a conexão local. Confira a rede e tente novamente.|Could not prepare the local connection. Check the network and try again.
Não foi possível salvar|Could not save
Não foi possível salvar a nova senha com segurança.|Could not safely save the new password.
Não foi possível salvar a nova senha.|Could not save the new password.
Não foi possível salvar as alterações.|Could not save changes.
Não foi possível salvar esta opção.|Could not save this option.
Não foi possível salvar esta preferência.|Could not save this preference.
Não foi possível salvar o estado completo do cofre.|Could not save the complete vault state.
Não foi possível validar as tentativas com segurança agora.|Could not safely validate sign-in attempts right now.
Não foi possível verificar agora.|Could not check right now.
Não informada|Not provided
Não informado|Not provided
Não será limpa automaticamente.|Will not be cleared automatically.
Números|Numbers
Números (0–9)|Numbers (0–9)
O Windows acessa apenas o cofre autorizado pelo celular.|Windows only accesses the vault authorized by the phone.
O armazenamento local do cofre precisa ser recuperado.|The local vault storage needs recovery.
O backup permanece criptografado e só pode ser restaurado neste mesmo cofre.|The backup stays encrypted and can only be restored to this same vault.
O celular autoriza o acesso. O computador apenas exibe o cofre durante a conexão.|Your phone authorizes access. The computer displays the vault while connected.
O celular foi desconectado.|The phone was disconnected.
O celular já está atendendo outra solicitação.|The phone is already handling another request.
O cofre ainda não foi criado.|The vault has not been created yet.
O cofre e a avaliação de senhas funcionam somente neste aparelho.|The vault and password analysis run on this device only.
O cofre já foi criado.|The vault already exists.
O cofre possui identificadores inválidos ou duplicados.|The vault has invalid or duplicate identifiers.
O cofre será bloqueado depois que o app ficar inativo.|The vault will lock after the app becomes inactive.
O computador não pôde ser autenticado.|The computer could not be authenticated.
O conteúdo atual do cofre será substituído pelo backup selecionado.|The current vault contents will be replaced by the selected backup.
O conteúdo do cofre foi substituído pelo backup selecionado.|The vault contents were replaced by the selected backup.
O conteúdo do cofre não pôde ser validado. Nenhum dado foi alterado.|The vault contents could not be validated. No data was changed.
O que deseja adicionar?|What would you like to add?
Observação (opcional)|Note (optional)
Ocultar senha|Hide password
Operação cancelada. Sua senha continua funcionando.|Operation canceled. Your password still works.
Organizar|Organize
Organizar senhas|Organize passwords
Os dados do cofre estão em um formato inválido.|The vault data has an invalid format.
Os dados do cofre não puderam ser lidos.|The vault data could not be read.
Ou detectar automaticamente|Or find automatically
Para sempre|Forever
Pareamento cancelado.|Pairing canceled.
Pareamento expirado.|Pairing expired.
Pareamento não autorizado.|Pairing not authorized.
Payload cifrado inválido.|Invalid encrypted payload.
Permita o acesso à câmera para ler o QR Code.|Allow camera access to scan the QR code.
Permitir captura de tela|Allow screenshots
Permitir reconexão por|Allow reconnection for
Personalizar senha|Customize password
Pessoal, trabalho ou faculdade|Personal, work or school
Política de privacidade|Privacy policy
Pontuação|Score
Preenchimento automático|Autofill
Preparando conexão local…|Preparing local connection…
Privacidade|Privacy
Procurando atualizações...|Checking for updates...
Procurando celular…|Searching for phone…
Procurando dispositivo|Searching for device
Procurando dispositivos na rede local|Searching for devices on the local network
Procurar celular|Find phone
Proteja suas senhas|Protect your passwords
Proteção|Protection
Provedor não identificado|Unknown provider
Pular esta etapa|Skip this step
QR Code de pareamento temporário|Temporary pairing QR code
QR Code expirado|QR code expired
QR Code inválido para o PassDrive.|Invalid PassDrive QR code.
QR Code inválido, expirado ou computador fora da rede. Confira e tente novamente.|Invalid or expired QR code, or the computer is offline. Check and try again.
Receber pedidos em segundo plano|Receive requests in the background
Recuperação|Recovery
Reinicie o app para concluir a alteração de captura de tela.|Restart the app to finish changing screenshot protection.
Reiniciar e instalar|Restart and install
Remove senhas copiadas automaticamente.|Automatically clears copied passwords.
Remover dos favoritos|Remove from favorites
Repita a nova senha|Repeat the new password
Resposta da base inválida.|Invalid database response.
Resposta da base muito grande.|Database response too large.
Restaurar|Restore
Restaurar backup|Restore backup
Restaurar backup?|Restore backup?
Resumo das senhas|Password summary
Reutilizadas|Reused
Revogar acesso|Revoke access
Reconecta automaticamente ao abrir o PassDrive no Windows, sem QR Code ou código.|Reconnects automatically when PassDrive opens on Windows, without a QR code or code.
Salvar alterações|Save changes
Salvar chave-mestra?|Save master key?
Salvar conta|Save account
Salvar nova senha|Save new password
Salvar serviço|Save service
Saúde das senhas|Password health
Se você perder a senha mestra e a chave-mestra, poderá perder o acesso ao cofre. Guarde as duas com segurança.|If you lose both the master password and master key, you may lose access to the vault. Keep both safe.
Segurança|Security
Seguras|Secure
Selecionar e restaurar|Select and restore
Sem conta vinculada|No linked account
Sem dados|No data
Sem prazo de expiração|No expiration date
Senha|Password
Senha atual|Current password
Senha do aplicativo|App password
Senha do app, biometria e bloqueio automático|App password, biometrics and auto-lock
Senha mestra|Master password
Senhas|Passwords
Senhas comprometidas verificadas|Compromised passwords checked
Serviço|Service
Serviços|Services
Será necessário parear novamente para acessar o cofre.|You will need to pair again to access the vault.
Sessão encerrada. Sincronize novamente.|Session ended. Sync again.
Sessão expirada. Conecte novamente.|Session expired. Connect again.
Seu cofre fica neste aparelho e é criptografado. A avaliação de força é local e não envia senhas para a internet. Senhas copiadas são limpas da área de transferência após 1 minuto.|Your encrypted vault stays on this device. Strength analysis is local and does not send passwords over the internet. Copied passwords are cleared from the clipboard after 1 minute.
Seu primeiro serviço começa aqui|Add your first service here
Seu usuário no serviço|Your username for this service
Sincronização e dispositivos|Sync and devices
Site|Website
Sobre|About
Sobre o PassDrive|About PassDrive
Solicitação cancelada no celular.|Request canceled on the phone.
Solicitação concluída no celular.|Request completed on the phone.
Solicitação repetida.|Duplicate request.
Somente favoritos|Favorites only
Sua senha e chave-mestra continuam disponíveis.|Your password and master key remain available.
Sua senha precisa ter pelo menos 8 caracteres.|Your password must have at least 8 characters.
Sua senha segura|Your secure password
Símbolos|Symbols
Símbolos (!@#$%)|Symbols (!@#$%)
Tamanho|Length
Tema, tamanho da fonte e idioma|Theme, font size and language
Tempo do bloqueio automático|Auto-lock delay
Tentar novamente|Try again
Termos de uso|Terms of use
URL ou domínio (opcional)|URL or domain (optional)
Um cofre local criptografado para organizar e proteger suas credenciais.|An encrypted local vault to organize and protect your credentials.
Uma anotação curta|A short note
Uma atualização importante de segurança precisa ser instalada para continuar usando o PassDrive.|An important security update must be installed to keep using PassDrive.
Uma nova versão do PassDrive está disponível. Ela será baixada enquanto você continua usando o app.|A new PassDrive version is available. It will download while you keep using the app.
Usar biometria|Use biometrics
Usar chave-mestra|Use master key
Usar esta senha|Use this password
Use as credenciais do PassDrive em sites e aplicativos. No Chrome, selecione “Autofill usando outro serviço”.|Use PassDrive credentials on websites and apps. In Chrome, select “Autofill using another service”.
Use o app PassDrive no celular para ler o código.|Use PassDrive on your phone to scan the code.
Use os caracteres exibidos no computador.|Use the characters shown on the computer.
Use senhas únicas para cada conta e guarde-as com segurança.|Use unique passwords for each account and store them securely.
Use sua digital para abrir o app.|Use your fingerprint to open the app.
Usuário|Username
Usuário (opcional)|Username (optional)
Ver senhas|View passwords
Verificado há 2 min|Checked 2 min ago
Verificando a rede local…|Checking the local network…
Verificando senhas comprometidas...|Checking for compromised passwords...
Versão 1.0.1|Version 1.0.1
Versão do banco de dados inválida.|Invalid database version.
Versão do cofre não suportada.|Unsupported vault version.
Versão, política e informações do app|Version, policies and app information
Visão geral|Overview
Você pode autorizar sem prazo depois, nas opções do dispositivo.|You can authorize without expiration later in the device options.
Voltar|Back
Vou baixar depois|Download later
''';
