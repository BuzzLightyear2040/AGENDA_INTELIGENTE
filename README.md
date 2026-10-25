# Agenda Inteligente (PokulAI)

Agenda médica por voz: plantões, exames, clientes e compromissos, com alerta de choque de horário e de deslocamento entre cidades, soma de horas e exames, faturamento estimado, insights e relatórios (PDF, Excel, CSV de deslocamentos). Funciona sozinha no navegador (modo local) ou sincronizada na nuvem com Supabase (celular + computador + equipe).

## Como ativar a nuvem (Supabase)

1. **Criar as tabelas** – no painel do Supabase do projeto, abra **SQL Editor → New query**, cole todo o conteúdo de
   [`supabase/migrations/20261025000000_agenda_schema.sql`](supabase/migrations/20261025000000_agenda_schema.sql) e clique em **Run**.
   O script só cria objetos com prefixo `agenda_` e pode ser executado de novo sem problemas.
2. **Pegar URL e chave** – em **Project Settings → API**: copie a *Project URL* e a chave **publishable** (`sb_publishable_...`) ou **anon**.
   Nunca use a chave `service_role` / `sb_secret_...` no app.
3. **URL do site no Auth** – em **Authentication → URL Configuration**, coloque o endereço onde o app está publicado
   (ex.: `https://seu-usuario.github.io/AGENDA_INTELIGENTE/`) em *Site URL* e em *Redirect URLs*. Isso faz os links de
   confirmação de e-mail e de troca de senha voltarem para a agenda.
4. **Configurar o app** – abra a agenda, toque na engrenagem ⚙ do menu lateral, cole URL e chave e salve.
   (Ou preencha `DEFAULT_SUPABASE_CONFIG` no `index.html` para que ninguém precise configurar.)
5. **Primeiro acesso** – digite e-mail e senha, toque em **Cadastrar**, confirme o e-mail e entre. A agenda pergunta o nome
   da sua agenda na nuvem e se deve enviar os dados que já estão no aparelho.

> O microfone e a confirmação de e-mail precisam que o app esteja publicado em **https** (GitHub Pages, Vercel, Netlify…).
> Aberto como arquivo local (`file://`) ele funciona no modo local, mas sem voz em alguns navegadores e sem os links de e-mail.

## Equipe (gestor e médicos)

- Quem cria a agenda é **gestor(a)**: vê e edita a agenda de todos, cadastra profissionais e locais e vê os relatórios da equipe.
- Para incluir um médico: cadastre o profissional em *Equipe e Profissionais* e toque no envelope ✉ para convidar pelo e-mail dele.
  Ele toca em **Cadastrar** com esse e-mail, confirma e, ao entrar, já cai na agenda da equipe.
- **Médicos** veem os locais e os colegas, mas só veem e lançam **a própria agenda**. Isso é garantido no banco (RLS), não só na tela.

## Lançamento por voz – exemplos

| Fala | Resultado |
|---|---|
| "plantão dia 5 em Jaboticaba" | usa a carga e o início padrão do local (ex.: 24h a partir das 7h) |
| "plantão dia 5 em Jaboticaba a partir das 19" | início 19h com a carga padrão do local |
| "exame dia 6 na Rádio Plan 20 exames das 8 às 17" | exame na Radiplan, 20 exames, valor calculado |
| "cliente sexta em Santa Maria das 14 às 15" | compromisso de cliente (fora do faturamento) |
| "… das 8 às 18 e depois em Planalto das 21 às 23" | dois lançamentos numa fala só |

Cadastre em cada local (ícone ⚙): cidade, **valor por hora**, **valor por exame**, **carga padrão do plantão** e **início padrão**.

## Testes das regras de segurança

```bash
psql -f supabase/tests/supabase_emulation.sql      # só em Postgres local de teste
psql -f supabase/migrations/20261025000000_agenda_schema.sql
psql -f supabase/tests/rls_test.sql
```
