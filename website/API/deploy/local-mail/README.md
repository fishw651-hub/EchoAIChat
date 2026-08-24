# Local Mail Stack

This folder contains a host-based local mail stack for the AIchat API server.

Goal:
- Run a local SMTP submission service on the same machine as the Go API
- Let `POST /api/v1/auth/send-code` send verification emails through `127.0.0.1`
- Support both local SMTP and external SMTP from the same backend code
- Enable TLS, SASL auth, and DKIM signing
- Provide DNS templates for SPF, DKIM, and DMARC

Recommended topology:

1. `mail.example.com` points to the same server as the API
2. Postfix listens on:
   - `25` for server-to-server delivery
   - `587` for authenticated submission with STARTTLS
   - `465` for implicit TLS if needed
3. Dovecot provides SASL auth for Postfix
4. OpenDKIM signs outbound mail
5. The AIchat API uses:
   - `host = 127.0.0.1`
   - `port = 587`
   - `tls_mode = starttls`
   - `auth_mode = plain`

## 1. Prepare DNS

Replace the placeholders with your real values.

### A record

```txt
mail.example.com.    IN A      YOUR_SERVER_IP
```

### MX record

```txt
example.com.         IN MX 10  mail.example.com.
```

### SPF record

```txt
example.com.         IN TXT    "v=spf1 mx a:mail.example.com ip4:YOUR_SERVER_IP -all"
```

### DKIM record

Run `scripts/generate_dkim.sh` first. It will create a public key.

```txt
default._domainkey.example.com. IN TXT "v=DKIM1; k=rsa; p=PASTE_PUBLIC_KEY_HERE"
```

### DMARC record

```txt
_dmarc.example.com.  IN TXT    "v=DMARC1; p=quarantine; adkim=s; aspf=s; rua=mailto:dmarc@example.com"
```

For stricter enforcement after warm-up:

```txt
_dmarc.example.com.  IN TXT    "v=DMARC1; p=reject; adkim=s; aspf=s; rua=mailto:dmarc@example.com"
```

## 2. Issue TLS certificates

Use Let's Encrypt for the mail host.

Example with Certbot:

```bash
sudo certbot certonly --standalone -d mail.example.com
```

Typical output:

```txt
/etc/letsencrypt/live/mail.example.com/fullchain.pem
/etc/letsencrypt/live/mail.example.com/privkey.pem
```

Those paths are referenced by the Postfix and Dovecot templates.

## 3. Render config files

Copy the example env file and fill it in:

```bash
cp mail.env.example mail.env
```

Then render the templates:

```bash
bash scripts/render_configs.sh mail.env
```

Rendered files are written to `./out`.

## 4. Install system packages

Ubuntu / Debian example:

```bash
sudo apt update
sudo apt install -y postfix dovecot-core dovecot-imapd opendkim opendkim-tools certbot
```

If you only need submission for outbound mail, Dovecot IMAP can still stay installed because it also provides auth sockets cleanly.

## 5. Copy rendered files

Example:

```bash
sudo cp out/postfix/main.cf /etc/postfix/main.cf
sudo cp out/postfix/master.cf /etc/postfix/master.cf
sudo cp out/dovecot/dovecot.conf /etc/dovecot/dovecot.conf
sudo cp out/dovecot/users /etc/dovecot/users
sudo cp out/opendkim/opendkim.conf /etc/opendkim.conf
sudo cp out/opendkim/KeyTable /etc/opendkim/KeyTable
sudo cp out/opendkim/SigningTable /etc/opendkim/SigningTable
sudo cp out/opendkim/TrustedHosts /etc/opendkim/TrustedHosts
```

Create mailbox storage and DKIM directories:

```bash
sudo mkdir -p /var/vmail/example.com/noreply
sudo mkdir -p /etc/opendkim/keys/example.com
sudo chown -R opendkim:opendkim /etc/opendkim/keys
sudo chmod 700 /etc/opendkim/keys/example.com
```

## 6. Create SMTP auth user

Use Dovecot's password generator:

```bash
doveadm pw -s SHA512-CRYPT
```

Then put the generated hash into `/etc/dovecot/users`, for example:

```txt
noreply@example.com:{SHA512-CRYPT}PASTE_HASH_HERE
```

The template file already includes the format.

## 7. Enable and restart services

```bash
sudo systemctl enable postfix dovecot opendkim
sudo systemctl restart opendkim
sudo systemctl restart dovecot
sudo systemctl restart postfix
```

## 8. Point AIchat to the local SMTP service

In the AIchat admin SMTP settings use:

```txt
Host: 127.0.0.1
Port: 587
Username: noreply@example.com
Password: <the Dovecot password you created>
From: noreply@example.com
TLS mode: starttls
Auth mode: plain
```

External SMTP still works too. For example:

```txt
Host: smtp.qq.com
Port: 465
Username: user@example.com
Password: auth-code
From: user@example.com
TLS mode: ssl
Auth mode: plain
```

## 9. Validation checklist

1. `openssl s_client -starttls smtp -connect mail.example.com:587`
2. `openssl s_client -connect mail.example.com:465`
3. `postfix check`
4. `doveconf -n`
5. `opendkim-testkey -d example.com -s default -vvv`
6. Send a test mail from the admin panel
7. Confirm the message contains a `DKIM-Signature` header

## 10. Security notes

- Do not keep `smtp_insecure_skip_verify` enabled in production
- Use `p=quarantine` first, then move to `p=reject`
- Keep the TLS cert readable by Postfix and Dovecot only
- Keep the DKIM private key readable by `opendkim` only
- Require auth on port `587`
- Do not expose an open relay
