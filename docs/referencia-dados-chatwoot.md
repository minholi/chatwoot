# Guia de Referência de Dados — Chatwoot

**Versão:** 1.0 | **Atualizado em:** 2026-03-23
**Plataforma:** Chatwoot (Ruby on Rails) | **Banco:** PostgreSQL

---

## Navegação Rápida

- [1. Visão Geral do Sistema](#1-visão-geral-do-sistema)
- [2. Fluxo de Negócio](#2-fluxo-de-negócio)
- [3. Referência Rápida das Tabelas Principais](#3-referência-rápida-das-tabelas-principais)
- [4. Dicionário de Dados por Módulo](#4-dicionário-de-dados-por-módulo)
- [5. Códigos de Status e Domínio](#5-códigos-de-status-e-domínio)
- [6. Padrões de JOIN entre Tabelas](#6-padrões-de-join-entre-tabelas)
- [7. Exemplos de Consultas SQL](#7-exemplos-de-consultas-sql)
- [8. Notas Técnicas Importantes](#8-notas-técnicas-importantes)

---

## 1. Visão Geral do Sistema

O Chatwoot é uma plataforma **omnichannel de suporte ao cliente** que centraliza atendimentos oriundos de múltiplos canais (WhatsApp, e-mail, web widget, Instagram, Telegram, etc.) em uma única interface. O banco de dados é **multi-tenant**: cada cliente da plataforma é uma `account`, e **toda query deve filtrar por `account_id`** para isolar os dados corretamente.

**Extensões PostgreSQL ativas:** `pg_trgm` (busca textual), `pgcrypto`, `plpgsql`, `vector` (embeddings para artigos de base de conhecimento).

| Grupo de tabelas | Domínio de dados |
|---|---|
| `accounts`, `account_users` | Contas e membros (agentes e admins) |
| `contacts`, `contact_inboxes`, `notes` | Contatos e sua presença nos canais |
| `inboxes`, `channel_*` | Canais de atendimento configurados |
| `conversations` | Conversas (entidade central do sistema) |
| `messages`, `attachments` | Mensagens trocadas em cada conversa |
| `users`, `teams`, `team_members`, `inbox_members` | Agentes e times |
| `labels`, `taggings` | Etiquetas para categorizar conversas |
| `csat_survey_responses` | Pesquisas de satisfação (CSAT) |
| `reporting_events` | Eventos de métricas (TFR, tempo de resolução) |
| `sla_policies`, `applied_slas` | Políticas e rastreamento de SLA |
| `notifications` | Notificações enviadas aos agentes |
| `automation_rules`, `campaigns`, `macros` | Automação e campanhas |
| `portals`, `articles` | Base de conhecimento (Help Center) |

---

## 2. Fluxo de Negócio

### Ciclo de vida de uma conversa

```
Contato chega via canal (WhatsApp, email, widget, Instagram...)
       |
       v
[contacts]          ← 1 registro por pessoa identificada por e-mail/telefone/identifier
[inboxes]           ← canal de origem (WhatsApp, Email, WebWidget, etc.)
       |
       | contato + inbox → contact_inbox criada (identidade do contato no canal)
       v
[contact_inboxes]   ← 1 registro por contato × inbox (source_id = ID no canal externo)
       |
       | nova conversa iniciada (pelo contato ou pelo agente via campanha)
       v
[conversations]     ← entidade central
  status            ← pending (aguardando) → open (em atendimento) → resolved (encerrado)
  assignee_id       ← agente responsável (FK → users)
  team_id           ← time responsável (opcional)
  display_id        ← número sequencial por account (gerado por trigger PostgreSQL)
       |
       ├── [messages]        ← mensagens trocadas (incoming / outgoing / activity)
       │     sender_id       ← polimórfico: User, Contact ou AgentBot
       │
       ├── [notifications]   ← notificações disparadas aos agentes
       ├── [mentions]        ← @menções de agentes dentro da conversa
       └── [csat_survey_responses]  ← pesquisa de satisfação (1 por conversa)
```

### Relacionamentos-chave entre tabelas

| Relação | Coluna FK | Tabela destino | Coluna destino |
|---|---|---|---|
| Conversa → Conta | `conversations.account_id` | `accounts` | `id` |
| Conversa → Inbox | `conversations.inbox_id` | `inboxes` | `id` |
| Conversa → Contato | `conversations.contact_id` | `contacts` | `id` |
| Conversa → Contact Inbox | `conversations.contact_inbox_id` | `contact_inboxes` | `id` |
| Conversa → Agente | `conversations.assignee_id` | `users` | `id` |
| Conversa → Time | `conversations.team_id` | `teams` | `id` |
| Mensagem → Conversa | `messages.conversation_id` | `conversations` | `id` |
| Mensagem → Sender | `messages.sender_id` + `sender_type` | `users` / `contacts` / `agent_bots` | `id` |
| Contact Inbox → Contato | `contact_inboxes.contact_id` | `contacts` | `id` |
| Contact Inbox → Inbox | `contact_inboxes.inbox_id` | `inboxes` | `id` |
| Inbox → Canal | `inboxes.channel_id` + `channel_type` | `channel_whatsapp` / `channel_email` / etc. | `id` |
| Membro de Time → Agente | `team_members.user_id` | `users` | `id` |
| Membro de Inbox → Agente | `inbox_members.user_id` | `users` | `id` |
| CSAT → Conversa | `csat_survey_responses.conversation_id` | `conversations` | `id` |
| CSAT → Agente | `csat_survey_responses.assigned_agent_id` | `users` | `id` |
| Reporting Event → Conversa | `reporting_events.conversation_id` | `conversations` | `id` |
| Reporting Event → Agente | `reporting_events.user_id` | `users` | `id` |
| Reporting Event → Inbox | `reporting_events.inbox_id` | `inboxes` | `id` |

---

## 3. Referência Rápida das Tabelas Principais

| Tabela | Chave Primária | Filtros Frequentes |
|---|---|---|
| `conversations` | `id` bigint | `account_id`, `status`, `inbox_id`, `assignee_id`, `team_id`, `created_at` |
| `messages` | `id` bigint | `account_id`, `conversation_id`, `message_type`, `created_at`, `private` |
| `contacts` | `id` bigint | `account_id`, `contact_type`, `last_activity_at`, `email`, `phone_number` |
| `contact_inboxes` | `id` bigint | `contact_id`, `inbox_id`, `source_id` |
| `inboxes` | `id` bigint | `account_id`, `channel_type` |
| `users` | `id` bigint | `email`, `availability` |
| `account_users` | composta (`account_id`, `user_id`) | `account_id`, `role`, `active_at` |
| `teams` | `id` bigint | `account_id` |
| `labels` | `id` bigint | `account_id`, `title` |
| `taggings` | `id` bigint | `taggable_type`, `taggable_id`, `tag_id`, `context` |
| `reporting_events` | `id` bigint | `account_id`, `name`, `created_at`, `inbox_id`, `user_id` |
| `csat_survey_responses` | `id` bigint | `account_id`, `assigned_agent_id`, `rating`, `created_at` |
| `notifications` | `id` bigint | `account_id`, `user_id`, `notification_type`, `read_at` |
| `sla_policies` | `id` bigint | `account_id` |
| `applied_slas` | `id` bigint | `account_id`, `conversation_id`, `sla_policy_id` |

---

## 4. Dicionário de Dados por Módulo

---

### 4.1 Módulo: Contas

#### Tabela: `accounts`

Cada registro representa uma empresa/workspace no Chatwoot.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `id` | bigint | NÃO | Chave primária |
| `name` | varchar | NÃO | Nome da conta |
| `status` | integer | NÃO | `0=active`, `1=suspended` |
| `locale` | integer | NÃO | Idioma padrão da conta |
| `domain` | varchar(100) | SIM | Domínio personalizado |
| `support_email` | varchar | SIM | E-mail de suporte exibido ao cliente |
| `auto_resolve_duration` | integer | SIM | Horas sem atividade para auto-resolver conversas |
| `feature_flags` | bigint | NÃO | Flags de funcionalidades habilitadas (bitmask) |
| `limits` | jsonb | SIM | Limites de uso (agentes, inboxes, etc.) |
| `custom_attributes` | jsonb | SIM | Atributos customizados da conta |
| `settings` | jsonb | SIM | Configurações gerais |
| `created_at` | datetime | NÃO | Data de criação |

#### Tabela: `account_users`

Vínculo entre usuários e contas — define o papel de cada agente em cada conta.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `account_id` | bigint | NÃO | FK → `accounts.id` |
| `user_id` | bigint | NÃO | FK → `users.id` |
| `role` | integer | NÃO | `0=agent`, `1=administrator` |
| `availability` | integer | NÃO | Disponibilidade do agente nessa conta |
| `auto_offline` | boolean | NÃO | Vai offline automaticamente ao fechar o navegador |
| `active_at` | datetime | SIM | Última vez que o agente esteve ativo |
| `custom_role_id` | bigint | SIM | FK → `custom_roles.id` (Enterprise) |
| `agent_capacity_policy_id` | bigint | SIM | FK → política de capacidade (Enterprise) |

---

### 4.2 Módulo: Contatos

#### Tabela: `contacts`

Representa os clientes/usuários finais que entram em contato via os canais configurados.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `id` | bigint | NÃO | Chave primária |
| `account_id` | bigint | NÃO | FK → `accounts.id` |
| `name` | varchar | SIM | Nome completo |
| `first_name` | varchar | SIM | Primeiro nome |
| `last_name` | varchar | SIM | Sobrenome |
| `email` | varchar | SIM | E-mail (único por account quando preenchido) |
| `phone_number` | varchar | SIM | Telefone no formato E.164 (ex: `+5511999999999`) |
| `identifier` | varchar | SIM | Identificador externo (único por account) |
| `contact_type` | integer | NÃO | `0=visitor`, `1=lead`, `2=customer` |
| `company_id` | bigint | SIM | FK → `companies.id` |
| `location` | varchar | SIM | Localização |
| `country_code` | varchar | SIM | Código do país (ISO 3166-1 alpha-2) |
| `blocked` | boolean | NÃO | Contato bloqueado (default: false) |
| `last_activity_at` | datetime | SIM | Última atividade registrada — principal campo para análises de recência |
| `additional_attributes` | jsonb | SIM | Atributos adicionais (ex: avatar_url, social profiles) |
| `custom_attributes` | jsonb | SIM | Atributos customizados definidos na conta. **Campo de integração:** `capt_codigo` armazena o ID do contato no CRM externo (ver nota 8.11) |
| `created_at` | datetime | NÃO | Data de criação do contato na base |

#### Tabela: `contact_inboxes`

Identidade do contato em um canal específico. Um contato pode estar em múltiplos canais.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `id` | bigint | NÃO | Chave primária |
| `contact_id` | bigint | NÃO | FK → `contacts.id` |
| `inbox_id` | bigint | NÃO | FK → `inboxes.id` |
| `source_id` | text | NÃO | Identificador do contato no canal externo (ex: número WhatsApp, page-scoped ID do Facebook) |
| `hmac_verified` | boolean | NÃO | Verificação HMAC do widget |
| `pubsub_token` | varchar | NÃO | Token para comunicação em tempo real |

#### Tabela: `notes`

Anotações internas sobre um contato (visíveis apenas para agentes).

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `id` | bigint | NÃO | Chave primária |
| `content` | text | NÃO | Conteúdo da nota |
| `contact_id` | bigint | NÃO | FK → `contacts.id` |
| `account_id` | bigint | NÃO | FK → `accounts.id` |
| `user_id` | bigint | SIM | FK → `users.id` — agente que criou a nota |
| `created_at` | datetime | NÃO | Data de criação |

---

### 4.3 Módulo: Inboxes / Canais

#### Tabela: `inboxes`

Representa os canais de atendimento configurados na conta (um WhatsApp, uma caixa de e-mail, um widget de chat, etc.).

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `id` | bigint | NÃO | Chave primária |
| `account_id` | bigint | NÃO | FK → `accounts.id` |
| `name` | varchar | NÃO | Nome do canal exibido na interface |
| `channel_id` | integer | NÃO | ID da tabela de canal específico |
| `channel_type` | varchar | NÃO | Tipo do canal (ver tabela abaixo) |
| `email` | varchar | SIM | E-mail associado ao canal (para email inboxes) |
| `greeting_enabled` | boolean | NÃO | Mensagem de boas-vindas habilitada |
| `enable_auto_assignment` | boolean | NÃO | Atribuição automática de agentes |
| `working_hours_enabled` | boolean | NÃO | Respeitar horário de funcionamento |
| `csat_survey_enabled` | boolean | NÃO | Enviar pesquisa CSAT ao resolver |
| `lock_to_single_conversation` | boolean | NÃO | Um contato só pode ter uma conversa aberta por vez nesse inbox |
| `sender_name_type` | integer | NÃO | `0=friendly` (nome do agente), `1=professional` (nome da conta) |
| `auto_assignment_config` | jsonb | SIM | Configuração da atribuição automática |
| `timezone` | varchar | NÃO | Fuso horário do inbox (default: "UTC") |
| `portal_id` | bigint | SIM | FK → `portals.id` — base de conhecimento vinculada |

#### Tipos de canal (`channel_type`)

| Valor | Tabela de configuração | Descrição |
|---|---|---|
| `Channel::Whatsapp` | `channel_whatsapp` | WhatsApp Business API (360dialog, Twilio, Meta) |
| `Channel::Email` | `channel_email` | Caixa de e-mail (IMAP/SMTP) |
| `Channel::WebWidget` | `channel_web_widgets` | Widget de chat no site |
| `Channel::Api` | `channel_api` | Canal via API customizada (webhook) |
| `Channel::FacebookPage` | `channel_facebook_pages` | Facebook Messenger |
| `Channel::Instagram` | `channel_instagram` | Instagram Direct |
| `Channel::Telegram` | `channel_telegram` | Bot no Telegram |
| `Channel::Sms` | `channel_sms` | SMS via Bandwidth/Twilio |
| `Channel::TwilioSms` | `channel_twilio_sms` | SMS via Twilio específico |
| `Channel::Twitter` | `channel_twitter_profiles` | Twitter/X DMs |
| `Channel::Line` | `channel_line` | LINE |
| `Channel::Tiktok` | `channel_tiktok` | TikTok Shop |
| `Channel::Voice` | `channel_voice` | Voz/Chamadas |

---

### 4.4 Módulo: Conversas

#### Tabela: `conversations`

Entidade central do Chatwoot. Cada atendimento é uma conversa vinculada a um contato, inbox e (opcionalmente) um agente e time.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `id` | bigint | NÃO | Chave primária global |
| `display_id` | integer | NÃO | ID sequencial **por account** (gerado por trigger) — use para referenciar conversas com usuários |
| `uuid` | uuid | NÃO | UUID único global |
| `account_id` | bigint | NÃO | FK → `accounts.id` |
| `inbox_id` | bigint | NÃO | FK → `inboxes.id` |
| `contact_id` | bigint | NÃO | FK → `contacts.id` |
| `contact_inbox_id` | bigint | SIM | FK → `contact_inboxes.id` |
| `assignee_id` | bigint | SIM | FK → `users.id` — agente responsável (NULL = não atribuída) |
| `team_id` | bigint | SIM | FK → `teams.id` — time responsável |
| `campaign_id` | bigint | SIM | FK → `campaigns.id` — campanha que originou a conversa |
| `sla_policy_id` | bigint | SIM | FK → `sla_policies.id` |
| `status` | integer | NÃO | `0=open`, `1=resolved`, `2=pending`, `3=snoozed` |
| `priority` | integer | SIM | `0=low`, `1=medium`, `2=high`, `3=urgent` (NULL = sem prioridade) |
| `identifier` | varchar | SIM | Identificador externo da conversa |
| `cached_label_list` | text | SIM | Lista de labels denormalizada (separada por vírgula) |
| `additional_attributes` | jsonb | SIM | Atributos adicionais |
| `custom_attributes` | jsonb | SIM | Atributos customizados definidos na conta |
| `created_at` | datetime | NÃO | Data de criação da conversa |
| `last_activity_at` | datetime | NÃO | Última atividade (mensagem ou evento) |
| `first_reply_created_at` | datetime | SIM | Data da primeira resposta do agente — base para cálculo do TFR |
| `waiting_since` | datetime | SIM | Desde quando a conversa aguarda resposta do agente |
| `snoozed_until` | datetime | SIM | Data de reativação automática para conversas adiadas |
| `contact_last_seen_at` | datetime | SIM | Última vez que o contato visualizou a conversa |
| `agent_last_seen_at` | datetime | SIM | Última vez que o agente visualizou a conversa |
| `assignee_last_seen_at` | datetime | SIM | Última vez que o agente atribuído visualizou |

---

### 4.5 Módulo: Mensagens

#### Tabela: `messages`

Todas as mensagens de todas as conversas. Inclui mensagens do contato, do agente, de bots e eventos de sistema (atividades).

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `id` | bigint | NÃO | Chave primária |
| `account_id` | bigint | NÃO | FK → `accounts.id` |
| `inbox_id` | bigint | NÃO | FK → `inboxes.id` |
| `conversation_id` | bigint | NÃO | FK → `conversations.id` |
| `sender_id` | bigint | SIM | FK polimórfico — ID do remetente |
| `sender_type` | varchar | SIM | Tipo do remetente: `'User'`, `'Contact'`, `'AgentBot'` |
| `message_type` | integer | NÃO | `0=incoming` (do contato), `1=outgoing` (do agente/bot), `2=activity` (evento de sistema), `3=template` |
| `content_type` | integer | NÃO | `0=text`, `1=input_text`, `2=input_textarea`, `3=input_email`, `4=input_select`, `5=cards`, `6=form`, `7=article`, `8=incoming_email`, `9=input_csat`, `10=integrations`, `11=sticker`, `12=voice_call` |
| `status` | integer | NÃO | `0=sent`, `1=delivered`, `2=read`, `3=failed` |
| `content` | text | SIM | Conteúdo textual da mensagem (máx 150k chars) |
| `processed_message_content` | text | SIM | Conteúdo processado (links tratados, etc.) |
| `private` | boolean | NÃO | Nota privada (visível apenas para agentes) |
| `source_id` | text | SIM | ID da mensagem no canal externo |
| `content_attributes` | json | SIM | Atributos específicos do tipo de conteúdo |
| `additional_attributes` | jsonb | SIM | Atributos adicionais |
| `created_at` | datetime | NÃO | Data de envio da mensagem |

#### Tabela: `attachments`

Arquivos anexados às mensagens.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `id` | bigint | NÃO | Chave primária |
| `message_id` | bigint | NÃO | FK → `messages.id` |
| `account_id` | bigint | NÃO | FK → `accounts.id` |
| `file_type` | integer | NÃO | `0=image`, `1=audio`, `2=video`, `3=file`, `4=location`, `5=fallback`, `6=share`, `7=story_mention`, `8=contact` |
| `external_url` | text | SIM | URL do arquivo no canal externo |
| `fallback_title` | varchar | SIM | Título de fallback |
| `coordinates_lat` | float | SIM | Latitude (para localizações) |
| `coordinates_long` | float | SIM | Longitude (para localizações) |

---

### 4.6 Módulo: Equipes e Agentes

#### Tabela: `users`

Agentes e administradores da plataforma.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `id` | bigint | NÃO | Chave primária |
| `name` | varchar | NÃO | Nome completo |
| `email` | varchar | NÃO | E-mail (único globalmente) |
| `availability` | integer | NÃO | `0=online`, `1=offline`, `2=busy` |
| `type` | varchar | SIM | STI: NULL para agentes normais |
| `custom_attributes` | jsonb | SIM | Atributos customizados |
| `ui_settings` | jsonb | SIM | Preferências de interface |
| `pubsub_token` | varchar | NÃO | Token único para WebSocket |
| `created_at` | datetime | NÃO | Data de criação |

#### Tabela: `teams`

Times de agentes dentro de uma conta.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `id` | bigint | NÃO | Chave primária |
| `account_id` | bigint | NÃO | FK → `accounts.id` |
| `name` | varchar | NÃO | Nome do time (único por account) |
| `description` | text | SIM | Descrição |
| `allow_auto_assign` | boolean | NÃO | Permite atribuição automática ao time |

#### Tabela: `team_members`

Vínculo agente ↔ time.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `team_id` | bigint | NÃO | FK → `teams.id` |
| `user_id` | bigint | NÃO | FK → `users.id` |

#### Tabela: `inbox_members`

Agentes com acesso a um inbox específico.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `inbox_id` | bigint | NÃO | FK → `inboxes.id` |
| `user_id` | bigint | NÃO | FK → `users.id` |

---

### 4.7 Módulo: Labels (Etiquetas)

#### Tabela: `labels`

Etiquetas criadas na conta para categorizar conversas.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `id` | bigint | NÃO | Chave primária |
| `account_id` | bigint | NÃO | FK → `accounts.id` |
| `title` | varchar | NÃO | Nome da etiqueta (único por account) |
| `description` | text | SIM | Descrição |
| `color` | varchar | NÃO | Cor hexadecimal (default: `#1f93ff`) |
| `show_on_sidebar` | boolean | NÃO | Exibir na barra lateral |

#### Tabela: `taggings`

Associação polimórfica de etiquetas a conversas (gem `acts-as-taggable-on`).

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `id` | bigint | NÃO | Chave primária |
| `tag_id` | bigint | NÃO | FK → `tags.id` |
| `taggable_type` | varchar | NÃO | Tipo da entidade (sempre `'Conversation'` para labels de conversa) |
| `taggable_id` | bigint | NÃO | ID da conversa |
| `tagger_type` | varchar | SIM | Tipo de quem aplicou a tag |
| `tagger_id` | bigint | SIM | ID de quem aplicou a tag |
| `context` | varchar | SIM | Contexto (sempre `'labels'`) |
| `created_at` | datetime | SIM | Data de aplicação |

> **Nota:** A tabela `tags` contém `id` e `name`. O `name` da tag corresponde ao `title` da label. Para cruzar, use `tags.name = labels.title AND labels.account_id = ?`

---

### 4.8 Módulo: CSAT

#### Tabela: `csat_survey_responses`

Respostas de pesquisas de satisfação (Customer Satisfaction). Uma por conversa resolvida (quando o inbox tem `csat_survey_enabled = true`).

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `id` | bigint | NÃO | Chave primária |
| `account_id` | bigint | NÃO | FK → `accounts.id` |
| `conversation_id` | bigint | NÃO | FK → `conversations.id` (unique) |
| `contact_id` | bigint | NÃO | FK → `contacts.id` |
| `message_id` | bigint | NÃO | FK → `messages.id` (unique) |
| `assigned_agent_id` | bigint | SIM | FK → `users.id` — agente atribuído no momento da resolução |
| `rating` | integer | NÃO | Nota dada pelo contato (tipicamente 1–5 ou emojis mapeados) |
| `feedback_message` | text | SIM | Comentário livre do contato |
| `csat_review_notes` | text | SIM | Notas do agente sobre o CSAT |
| `review_notes_updated_by_id` | bigint | SIM | FK → `users.id` — quem editou as notas |
| `review_notes_updated_at` | datetime | SIM | Quando as notas foram editadas |
| `created_at` | datetime | NÃO | Data de resposta |

---

### 4.9 Módulo: Relatórios

#### Tabela: `reporting_events`

Eventos de métricas registrados pelo sistema para alimentar relatórios de desempenho. Cada linha representa um evento mensurável (primeira resposta, resolução, etc.).

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `id` | bigint | NÃO | Chave primária |
| `account_id` | bigint | NÃO | FK → `accounts.id` |
| `inbox_id` | bigint | SIM | FK → `inboxes.id` |
| `user_id` | bigint | SIM | FK → `users.id` — agente relacionado ao evento |
| `conversation_id` | bigint | SIM | FK → `conversations.id` |
| `name` | varchar | NÃO | Nome do evento (ver domínio abaixo) |
| `value` | float | SIM | Duração em segundos (total) |
| `value_in_business_hours` | float | SIM | Duração em segundos dentro do horário de funcionamento |
| `event_start_time` | datetime | SIM | Início do período medido |
| `event_end_time` | datetime | SIM | Fim do período medido |
| `created_at` | datetime | NÃO | Data do registro |

**Valores de `name`:**

| Nome do evento | Descrição |
|---|---|
| `first_response_time` | Tempo até a primeira resposta do agente (segundos) |
| `resolution_time` | Tempo total até resolver a conversa (segundos) |
| `reply_time` | Tempo de resposta em mensagens subsequentes |
| `bot_handoff` | Transferência do bot para agente humano |
| `conversation_created` | Criação de conversa (para contagem de volume) |

---

### 4.10 Módulo: SLA

#### Tabela: `sla_policies`

Políticas de SLA configuradas na conta.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `id` | bigint | NÃO | Chave primária |
| `account_id` | bigint | NÃO | FK → `accounts.id` |
| `name` | varchar | NÃO | Nome da política |
| `description` | text | SIM | Descrição |
| `first_response_time_threshold` | integer | SIM | Limite de TFR em segundos |
| `next_response_time_threshold` | integer | SIM | Limite de próxima resposta em segundos |
| `resolution_time_threshold` | integer | SIM | Limite de resolução em segundos |
| `only_during_business_hours` | boolean | NÃO | Contar apenas em horário comercial |

#### Tabela: `applied_slas`

Rastreamento da aplicação de SLA por conversa.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `id` | bigint | NÃO | Chave primária |
| `account_id` | bigint | NÃO | FK → `accounts.id` |
| `conversation_id` | bigint | NÃO | FK → `conversations.id` |
| `sla_policy_id` | bigint | NÃO | FK → `sla_policies.id` |
| `sla_status` | varchar | SIM | Status atual do SLA (`active`, `breached`, `fulfilled`) |

---

### 4.11 Módulo: Notificações

#### Tabela: `notifications`

Notificações geradas pelo sistema para os agentes (aparecem no sino de notificações).

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `id` | bigint | NÃO | Chave primária |
| `account_id` | bigint | NÃO | FK → `accounts.id` |
| `user_id` | bigint | NÃO | FK → `users.id` — destinatário |
| `notification_type` | integer | NÃO | Tipo da notificação (ver domínio) |
| `primary_actor_type` | varchar | NÃO | Tipo da entidade principal: `'Conversation'` |
| `primary_actor_id` | bigint | NÃO | FK polimórfico — ID da conversa |
| `secondary_actor_type` | varchar | SIM | Tipo da entidade secundária: `'Message'` |
| `secondary_actor_id` | bigint | SIM | FK polimórfico — ID da mensagem |
| `read_at` | datetime | SIM | Data de leitura (NULL = não lida) |
| `snoozed_until` | datetime | SIM | Adiada até esta data |
| `last_activity_at` | datetime | NÃO | Última atualização |
| `meta` | jsonb | SIM | Metadados adicionais |

---

## 5. Códigos de Status e Domínio

### 5.1 `conversations.status`

| Valor numérico | Nome | Descrição |
|---|---|---|
| `0` | `open` | Conversa aberta, aguardando ou em atendimento |
| `1` | `resolved` | Conversa encerrada/resolvida |
| `2` | `pending` | Aguardando ação do agente (ex: canal com bot) |
| `3` | `snoozed` | Conversa adiada — reativará em `snoozed_until` |

### 5.2 `conversations.priority`

| Valor numérico | Nome | Descrição |
|---|---|---|
| `NULL` | — | Sem prioridade definida |
| `0` | `low` | Baixa |
| `1` | `medium` | Média |
| `2` | `high` | Alta |
| `3` | `urgent` | Urgente |

### 5.3 `messages.message_type`

| Valor numérico | Nome | Descrição |
|---|---|---|
| `0` | `incoming` | Mensagem enviada pelo contato |
| `1` | `outgoing` | Mensagem enviada pelo agente ou bot |
| `2` | `activity` | Evento de sistema (ex: "conversa atribuída ao agente X") |
| `3` | `template` | Mensagem de template (ex: HSM do WhatsApp) |

### 5.4 `messages.status`

| Valor numérico | Nome | Descrição |
|---|---|---|
| `0` | `sent` | Enviada |
| `1` | `delivered` | Entregue ao destinatário |
| `2` | `read` | Lida pelo destinatário |
| `3` | `failed` | Falha no envio |

### 5.5 `messages.content_type`

| Valor numérico | Nome | Descrição |
|---|---|---|
| `0` | `text` | Texto simples |
| `1` | `input_text` | Campo de input de texto (formulário bot) |
| `2` | `input_textarea` | Campo de textarea (formulário bot) |
| `3` | `input_email` | Campo de e-mail (formulário bot) |
| `4` | `input_select` | Dropdown de seleção (formulário bot) |
| `5` | `cards` | Cards (carrossel) |
| `6` | `form` | Formulário bot |
| `7` | `article` | Artigo da base de conhecimento |
| `8` | `incoming_email` | E-mail recebido |
| `9` | `input_csat` | Pesquisa CSAT |
| `10` | `integrations` | Integrações |
| `11` | `sticker` | Sticker/Figurinha |
| `12` | `voice_call` | Chamada de voz |

### 5.6 `contacts.contact_type`

| Valor numérico | Nome | Descrição |
|---|---|---|
| `0` | `visitor` | Visitante anônimo |
| `1` | `lead` | Lead identificado |
| `2` | `customer` | Cliente ativo |

### 5.7 `users.availability`

| Valor numérico | Nome | Descrição |
|---|---|---|
| `0` | `online` | Disponível |
| `1` | `offline` | Offline |
| `2` | `busy` | Ocupado |

### 5.8 `account_users.role`

| Valor numérico | Nome | Descrição |
|---|---|---|
| `0` | `agent` | Agente (acesso ao atendimento) |
| `1` | `administrator` | Administrador (acesso às configurações) |

### 5.9 `notifications.notification_type`

| Valor numérico | Nome | Descrição |
|---|---|---|
| `1` | `conversation_creation` | Nova conversa criada |
| `2` | `conversation_assignment` | Conversa atribuída ao agente |
| `3` | `assigned_conversation_new_message` | Nova mensagem em conversa atribuída |
| `4` | `conversation_mention` | Agente foi @mencionado |
| `5` | `participating_conversation_new_message` | Nova mensagem em conversa que participa |
| `6` | `sla_missed_first_response` | SLA de primeira resposta violado |
| `7` | `sla_missed_next_response` | SLA de próxima resposta violado |
| `8` | `sla_missed_resolution` | SLA de resolução violado |

### 5.10 `attachments.file_type`

| Valor numérico | Nome |
|---|---|
| `0` | `image` |
| `1` | `audio` |
| `2` | `video` |
| `3` | `file` |
| `4` | `location` |
| `5` | `fallback` |
| `6` | `share` |
| `7` | `story_mention` |
| `8` | `contact` |

---

## 6. Padrões de JOIN entre Tabelas

### 6.1 Conversa → Agente → Time

```sql
SELECT
    c.id,
    c.display_id,
    c.status,
    u.name AS agente,
    t.name AS time
FROM conversations c
LEFT JOIN users u ON u.id = c.assignee_id
LEFT JOIN teams t ON t.id = c.team_id
WHERE c.account_id = 1
```

### 6.2 Conversa → Contato → Inbox (com tipo de canal)

```sql
SELECT
    c.display_id,
    co.name AS contato,
    co.email,
    co.phone_number,
    i.name AS inbox,
    i.channel_type
FROM conversations c
JOIN contacts co ON co.id = c.contact_id
JOIN inboxes i ON i.id = c.inbox_id
WHERE c.account_id = 1
```

### 6.3 Mensagem → Sender (polimórfico)

```sql
-- Mensagens com nome do remetente (agente ou contato)
SELECT
    m.id,
    m.content,
    m.message_type,
    m.created_at,
    CASE
        WHEN m.sender_type = 'User'    THEN u.name
        WHEN m.sender_type = 'Contact' THEN co.name
        ELSE 'Bot'
    END AS remetente
FROM messages m
LEFT JOIN users u    ON u.id = m.sender_id AND m.sender_type = 'User'
LEFT JOIN contacts co ON co.id = m.sender_id AND m.sender_type = 'Contact'
WHERE m.account_id = 1
  AND m.conversation_id = 123
ORDER BY m.created_at
```

### 6.4 Conversa → Labels (via taggings)

```sql
SELECT
    c.display_id,
    c.status,
    string_agg(t.name, ', ') AS labels
FROM conversations c
JOIN taggings tg ON tg.taggable_id = c.id
                 AND tg.taggable_type = 'Conversation'
                 AND tg.context = 'labels'
JOIN tags t ON t.id = tg.tag_id
WHERE c.account_id = 1
GROUP BY c.id, c.display_id, c.status
```

### 6.5 Conversa com todas as labels numa linha (usando cached_label_list)

```sql
-- Mais performático: usa o campo denormalizado cached_label_list
SELECT
    c.display_id,
    c.status,
    c.cached_label_list AS labels
FROM conversations c
WHERE c.account_id = 1
  AND c.cached_label_list LIKE '%suporte%'
```

### 6.6 Agente → Todas as contas e papéis

```sql
SELECT
    u.name AS agente,
    u.email,
    a.name AS conta,
    au.role,
    au.active_at
FROM users u
JOIN account_users au ON au.user_id = u.id
JOIN accounts a ON a.id = au.account_id
ORDER BY a.name, u.name
```

### 6.7 Conversa → Reporting Events (métricas)

```sql
SELECT
    c.display_id,
    re.name AS metrica,
    re.value AS segundos,
    ROUND(re.value / 3600.0, 2) AS horas,
    re.value_in_business_hours AS segundos_horario_comercial
FROM conversations c
JOIN reporting_events re ON re.conversation_id = c.id
WHERE c.account_id = 1
  AND re.name IN ('first_response_time', 'resolution_time')
```

### 6.8 Notificação → Conversa (primary_actor polimórfico)

```sql
SELECT
    n.id,
    n.notification_type,
    n.read_at,
    u.name AS destinatario,
    c.display_id AS conversa
FROM notifications n
JOIN users u ON u.id = n.user_id
JOIN conversations c ON c.id = n.primary_actor_id
                     AND n.primary_actor_type = 'Conversation'
WHERE n.account_id = 1
  AND n.read_at IS NULL
ORDER BY n.last_activity_at DESC
```

### 6.9 CSAT → Conversa → Agente → Inbox

```sql
SELECT
    cs.rating,
    cs.feedback_message,
    cs.created_at,
    c.display_id AS conversa,
    u.name AS agente,
    i.name AS inbox
FROM csat_survey_responses cs
JOIN conversations c ON c.id = cs.conversation_id
JOIN inboxes i ON i.id = c.inbox_id
LEFT JOIN users u ON u.id = cs.assigned_agent_id
WHERE cs.account_id = 1
```

---

## 7. Exemplos de Consultas SQL

### 7.1 Volume de Conversas por Status e Inbox

```sql
-- Conversas abertas e pendentes agrupadas por inbox
SELECT
    i.name AS inbox,
    i.channel_type,
    COUNT(CASE WHEN c.status = 0 THEN 1 END) AS abertas,
    COUNT(CASE WHEN c.status = 2 THEN 1 END) AS pendentes,
    COUNT(CASE WHEN c.status = 1 THEN 1 END) AS resolvidas,
    COUNT(*) AS total
FROM conversations c
JOIN inboxes i ON i.id = c.inbox_id
WHERE c.account_id = 1
  AND c.created_at >= NOW() - INTERVAL '30 days'
GROUP BY i.id, i.name, i.channel_type
ORDER BY total DESC
```

### 7.2 Desempenho dos Agentes (TFR e Tempo de Resolução)

```sql
-- Tempo médio de primeira resposta e resolução por agente no mês
SELECT
    u.name AS agente,
    COUNT(DISTINCT CASE WHEN re.name = 'first_response_time' THEN re.conversation_id END) AS conversas_respondidas,
    ROUND(AVG(CASE WHEN re.name = 'first_response_time' THEN re.value END) / 60.0, 1) AS tfr_medio_minutos,
    ROUND(AVG(CASE WHEN re.name = 'resolution_time' THEN re.value END) / 3600.0, 1) AS resolucao_media_horas,
    COUNT(DISTINCT CASE WHEN re.name = 'resolution_time' THEN re.conversation_id END) AS conversas_resolvidas
FROM reporting_events re
JOIN users u ON u.id = re.user_id
WHERE re.account_id = 1
  AND re.created_at >= DATE_TRUNC('month', NOW())
  AND re.name IN ('first_response_time', 'resolution_time')
GROUP BY u.id, u.name
ORDER BY conversas_resolvidas DESC
```

### 7.3 Relatório de CSAT por Agente e Inbox

```sql
-- CSAT do último mês: média de avaliação por agente e inbox
SELECT
    u.name AS agente,
    i.name AS inbox,
    COUNT(*) AS total_avaliacoes,
    ROUND(AVG(cs.rating), 2) AS media_rating,
    COUNT(CASE WHEN cs.rating >= 4 THEN 1 END) AS satisfeitos,
    COUNT(CASE WHEN cs.rating <= 2 THEN 1 END) AS insatisfeitos,
    ROUND(COUNT(CASE WHEN cs.rating >= 4 THEN 1 END) * 100.0 / COUNT(*), 1) AS pct_satisfeitos
FROM csat_survey_responses cs
JOIN conversations c ON c.id = cs.conversation_id
JOIN inboxes i ON i.id = c.inbox_id
LEFT JOIN users u ON u.id = cs.assigned_agent_id
WHERE cs.account_id = 1
  AND cs.created_at >= NOW() - INTERVAL '30 days'
GROUP BY u.id, u.name, i.id, i.name
HAVING COUNT(*) >= 5
ORDER BY media_rating DESC
```

### 7.4 Conversas Abertas Sem Atribuição (Unassigned)

```sql
-- Conversas abertas ou pendentes sem agente nem time atribuído, com tempo de espera
SELECT
    c.display_id,
    co.name AS contato,
    co.phone_number,
    i.name AS inbox,
    c.status,
    c.created_at,
    EXTRACT(EPOCH FROM (NOW() - c.created_at)) / 3600.0 AS horas_aguardando,
    c.cached_label_list AS labels
FROM conversations c
JOIN contacts co ON co.id = c.contact_id
JOIN inboxes i ON i.id = c.inbox_id
WHERE c.account_id = 1
  AND c.status IN (0, 2)        -- open ou pending
  AND c.assignee_id IS NULL
  AND c.team_id IS NULL
ORDER BY c.created_at ASC
```

### 7.5 SLA — Conversas em Breach por Política

```sql
-- Conversas que violaram o SLA de primeira resposta
SELECT
    c.display_id,
    co.name AS contato,
    i.name AS inbox,
    sp.name AS politica_sla,
    sp.first_response_time_threshold / 60 AS limite_tfr_minutos,
    re.value / 60.0 AS tfr_real_minutos,
    ROUND(re.value / 60.0 - sp.first_response_time_threshold / 60.0, 1) AS excesso_minutos,
    c.created_at
FROM conversations c
JOIN contacts co ON co.id = c.contact_id
JOIN inboxes i ON i.id = c.inbox_id
JOIN sla_policies sp ON sp.id = c.sla_policy_id
JOIN reporting_events re ON re.conversation_id = c.id
                         AND re.name = 'first_response_time'
WHERE c.account_id = 1
  AND re.value > sp.first_response_time_threshold
  AND c.created_at >= NOW() - INTERVAL '7 days'
ORDER BY excesso_minutos DESC
```

### 7.6 Análise de Volume por Semana (Funil de Status)

```sql
-- Conversas criadas por semana e status de encerramento
SELECT
    DATE_TRUNC('week', c.created_at)::date AS semana,
    COUNT(*) AS total_criadas,
    COUNT(CASE WHEN c.status = 1 THEN 1 END) AS resolvidas,
    COUNT(CASE WHEN c.status = 0 THEN 1 END) AS ainda_abertas,
    ROUND(COUNT(CASE WHEN c.status = 1 THEN 1 END) * 100.0 / COUNT(*), 1) AS taxa_resolucao_pct
FROM conversations c
WHERE c.account_id = 1
  AND c.created_at >= NOW() - INTERVAL '90 days'
GROUP BY DATE_TRUNC('week', c.created_at)
ORDER BY semana DESC
```

### 7.7 Contatos Mais Ativos (Recência)

```sql
-- Top contatos por recência de atividade e quantidade de conversas
SELECT
    co.name AS contato,
    co.email,
    co.phone_number,
    co.contact_type,
    co.last_activity_at,
    COUNT(c.id) AS total_conversas,
    COUNT(CASE WHEN c.status = 0 THEN 1 END) AS conversas_abertas,
    COUNT(CASE WHEN c.status = 1 THEN 1 END) AS conversas_resolvidas
FROM contacts co
LEFT JOIN conversations c ON c.contact_id = co.id AND c.account_id = co.account_id
WHERE co.account_id = 1
  AND co.last_activity_at IS NOT NULL
GROUP BY co.id, co.name, co.email, co.phone_number, co.contact_type, co.last_activity_at
ORDER BY co.last_activity_at DESC
LIMIT 100
```

### 7.8 Análise de Times — Conversas por Time e Status

```sql
-- Volume de conversas por time com tempo médio de resolução
SELECT
    t.name AS time,
    COUNT(c.id) AS total_conversas,
    COUNT(CASE WHEN c.status = 0 THEN 1 END) AS abertas,
    COUNT(CASE WHEN c.status = 1 THEN 1 END) AS resolvidas,
    COUNT(CASE WHEN c.status = 2 THEN 1 END) AS pendentes,
    ROUND(AVG(CASE WHEN re.name = 'resolution_time' THEN re.value END) / 3600.0, 1) AS resolucao_media_horas
FROM teams t
JOIN conversations c ON c.team_id = t.id AND c.account_id = t.account_id
LEFT JOIN reporting_events re ON re.conversation_id = c.id AND re.name = 'resolution_time'
WHERE t.account_id = 1
  AND c.created_at >= NOW() - INTERVAL '30 days'
GROUP BY t.id, t.name
ORDER BY total_conversas DESC
```

### 7.9 Histórico Completo de um Contato

```sql
-- Todas as conversas e mensagens de um contato específico
WITH contato_conversas AS (
    SELECT c.id AS conv_id, c.display_id, c.status, c.created_at AS conv_criada,
           i.name AS inbox, i.channel_type,
           u.name AS agente_atual
    FROM conversations c
    JOIN inboxes i ON i.id = c.inbox_id
    LEFT JOIN users u ON u.id = c.assignee_id
    WHERE c.contact_id = 456   -- substituir pelo ID do contato
      AND c.account_id = 1
)
SELECT
    cc.display_id AS conversa,
    cc.inbox,
    cc.channel_type,
    cc.agente_atual,
    cc.status AS status_conversa,
    m.message_type,
    m.content,
    m.created_at AS data_mensagem,
    CASE
        WHEN m.sender_type = 'User'    THEN u2.name
        WHEN m.sender_type = 'Contact' THEN 'Contato'
        ELSE 'Bot'
    END AS remetente
FROM contato_conversas cc
JOIN messages m ON m.conversation_id = cc.conv_id AND m.account_id = 1
LEFT JOIN users u2 ON u2.id = m.sender_id AND m.sender_type = 'User'
WHERE m.message_type IN (0, 1)   -- apenas incoming e outgoing (sem eventos de sistema)
  AND m.private = false
ORDER BY cc.conv_criada DESC, m.created_at
```

### 7.10 Ranking de Mensagens por Inbox e Tipo

```sql
-- Volume de mensagens por inbox, tipo e dia — útil para dimensionar carga
SELECT
    i.name AS inbox,
    i.channel_type,
    DATE_TRUNC('day', m.created_at)::date AS dia,
    COUNT(CASE WHEN m.message_type = 0 THEN 1 END) AS mensagens_recebidas,
    COUNT(CASE WHEN m.message_type = 1 THEN 1 END) AS mensagens_enviadas,
    COUNT(CASE WHEN m.message_type = 2 THEN 1 END) AS eventos_sistema,
    COUNT(*) AS total
FROM messages m
JOIN inboxes i ON i.id = m.inbox_id
WHERE m.account_id = 1
  AND m.created_at >= NOW() - INTERVAL '30 days'
GROUP BY i.id, i.name, i.channel_type, DATE_TRUNC('day', m.created_at)
ORDER BY dia DESC, total DESC
```

### 7.11 Agentes Online Agora (Disponibilidade Atual)

```sql
-- Agentes de uma conta com disponibilidade atual
SELECT
    u.name AS agente,
    u.email,
    au.role,
    au.availability,
    CASE au.availability
        WHEN 0 THEN 'Online'
        WHEN 1 THEN 'Offline'
        WHEN 2 THEN 'Ocupado'
    END AS disponibilidade,
    au.active_at AS ultima_atividade,
    COUNT(DISTINCT c.id) AS conversas_atribuidas_abertas
FROM account_users au
JOIN users u ON u.id = au.user_id
LEFT JOIN conversations c ON c.assignee_id = u.id
                          AND c.account_id = au.account_id
                          AND c.status = 0   -- open
WHERE au.account_id = 1
GROUP BY u.id, u.name, u.email, au.role, au.availability, au.active_at
ORDER BY au.availability, conversas_atribuidas_abertas DESC
```

### 7.12 Integração com CRM — Contatos com `capt_codigo`

```sql
-- Contatos do Chatwoot que possuem vínculo com o CRM,
-- com suas conversas mais recentes
SELECT
    co.id AS chatwoot_contact_id,
    co.custom_attributes->>'capt_codigo' AS crm_contato_id,
    co.name,
    co.email,
    co.phone_number,
    co.contact_type,
    co.last_activity_at,
    COUNT(c.id) AS total_conversas,
    COUNT(CASE WHEN c.status = 0 THEN 1 END) AS conversas_abertas,
    MAX(c.created_at) AS ultima_conversa_em
FROM contacts co
LEFT JOIN conversations c ON c.contact_id = co.id AND c.account_id = co.account_id
WHERE co.account_id = 1
  AND co.custom_attributes ? 'capt_codigo'
  AND co.custom_attributes->>'capt_codigo' IS NOT NULL
  AND co.custom_attributes->>'capt_codigo' <> ''
GROUP BY co.id, co.name, co.email, co.phone_number, co.contact_type, co.last_activity_at
ORDER BY co.last_activity_at DESC NULLS LAST
```

```sql
-- Buscar contato do Chatwoot pelo ID do CRM
SELECT
    co.id AS chatwoot_contact_id,
    co.name,
    co.email,
    co.phone_number,
    co.custom_attributes->>'capt_codigo' AS crm_contato_id
FROM contacts co
WHERE co.account_id = 1
  AND co.custom_attributes->>'capt_codigo' = '123'  -- substituir pelo ID do CRM
```

```sql
-- Contatos do CRM sem vínculo no Chatwoot (não têm capt_codigo preenchido)
SELECT
    COUNT(*) AS total_contatos,
    COUNT(CASE WHEN custom_attributes ? 'capt_codigo'
               AND custom_attributes->>'capt_codigo' <> '' THEN 1 END) AS vinculados_crm,
    COUNT(CASE WHEN NOT (custom_attributes ? 'capt_codigo')
               OR custom_attributes->>'capt_codigo' = '' THEN 1 END) AS sem_vinculo_crm
FROM contacts
WHERE account_id = 1
```

---

## 8. Notas Técnicas Importantes

### 8.1 Multi-tenancy — `account_id` obrigatório

**Toda query deve incluir `WHERE account_id = ?`** na tabela principal. O banco não tem separação física por tenant; misturar dados de contas diferentes é o erro mais comum em análises.

### 8.2 Enums são inteiros no banco

Os campos de status são armazenados como **inteiros** no PostgreSQL, não como strings. Use sempre o valor numérico:

```sql
-- CORRETO
WHERE status = 0          -- open
WHERE message_type = 1    -- outgoing

-- ERRADO (não funciona)
WHERE status = 'open'
```

### 8.3 `display_id` vs `id`

- `conversations.id` → chave primária global (use em JOINs)
- `conversations.display_id` → número sequencial **por account** (use para referenciar com usuários)
- Para buscar uma conversa pelo número que aparece na interface: `WHERE account_id = 1 AND display_id = 123`

### 8.4 Labels em conversas — dois métodos

**Método 1 — Campo denormalizado (rápido):**
```sql
WHERE cached_label_list LIKE '%nome-da-label%'
```

**Método 2 — JOIN completo (preciso, use para agrupar por label):**
```sql
JOIN taggings tg ON tg.taggable_id = c.id
                 AND tg.taggable_type = 'Conversation'
                 AND tg.context = 'labels'
JOIN tags t ON t.id = tg.tag_id
WHERE t.name = 'nome-da-label'
```

### 8.5 Sender polimórfico em `messages`

O campo `sender_type` pode ser `'User'`, `'Contact'` ou `'AgentBot'`. Para fazer LEFT JOINs corretos:

```sql
LEFT JOIN users u    ON u.id = m.sender_id AND m.sender_type = 'User'
LEFT JOIN contacts c ON c.id = m.sender_id AND m.sender_type = 'Contact'
```

### 8.6 `reporting_events` — métricas derivadas

- Os valores em `value` são **segundos** (float). Divida por 60 para minutos, 3600 para horas.
- `value_in_business_hours` considera apenas o horário de funcionamento configurado no inbox.
- Um mesmo `conversation_id` pode ter múltiplos eventos do mesmo `name` se a conversa foi reaberta.

### 8.7 Trigger PostgreSQL para `display_id`

O `display_id` é gerado por um trigger `BEFORE INSERT` que usa sequences PostgreSQL no formato `conv_dpid_seq_{account_id}`. Não tente gerar ou manipular esse valor manualmente.

### 8.8 Busca textual em mensagens

O banco tem índice GIN `pg_trgm` na coluna `messages.content`. Para busca eficiente:

```sql
WHERE content ILIKE '%termo%'
-- ou com operador trgm para relevância:
WHERE content % 'termo'
```

### 8.9 Conversas sem resposta do agente

"Waiting since" indica desde quando a conversa aguarda resposta do agente:

```sql
WHERE waiting_since IS NOT NULL
  AND status = 0   -- open
ORDER BY waiting_since ASC
```

### 8.11 Custom Attributes — `capt_codigo` (integração com CRM)

O campo `contacts.custom_attributes` é um jsonb livre. Os atributos customizados são definidos na interface do Chatwoot e gravados pela integração.

**Campo padrão de integração:** `capt_codigo` — armazena o ID do contato no CRM externo (directorcrm). Usado para vincular dados de atendimento (Chatwoot) com dados de captação/inscrição/matrícula (CRM).

**Sintaxe PostgreSQL para campos jsonb:**

```sql
-- Extrair valor como texto
custom_attributes->>'capt_codigo'

-- Testar se a chave existe
custom_attributes ? 'capt_codigo'

-- Filtrar contatos vinculados ao CRM
WHERE custom_attributes->>'capt_codigo' IS NOT NULL
  AND custom_attributes->>'capt_codigo' <> ''

-- Buscar por ID específico do CRM
WHERE custom_attributes->>'capt_codigo' = '456'

-- Outros exemplos de acesso jsonb
custom_attributes->>'outro_campo'          -- valor como texto
(custom_attributes->>'numero')::integer    -- cast para inteiro
custom_attributes->'objeto_aninhado'       -- retorna jsonb (não texto)
```

> **Atenção:** O operador `?` para verificar existência de chave pode precisar de escape em alguns drivers SQL. Se houver erro, use: `custom_attributes @> '{"capt_codigo": null}'::jsonb` não funciona para null; prefira `custom_attributes->>'capt_codigo' IS NOT NULL`.

### 8.10 Conversas `pending` vs `open`

- `pending (2)` → tipicamente conversas vindas de canais com bot, aguardando triagem humana
- `open (0)` → em atendimento ativo pelo agente
- A transição `pending → open` ocorre quando o agente responde ou a conversa é atribuída manualmente
