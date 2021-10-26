# smtp-sink container

## synopsis

```sh
docker build --tag smtp-sink:3.6.2 .
# or
docker build --tag smtp-sink:3.6.2-busybox --target busybox .
# or
docker build --tag smtp-sink:3.6.2-alpine --target alpine .

docker run --name smtp-sink --publish 1025:1025 --rm smtp-sink:3.6.2
```

## caveats

- **no authentication**: Although *smtp-sink* can be configured to announce PLAIN and LOGIN authentication support, it does not respond well to AUTH requests. Clients might expect a 334 (continue) or 235 (authentication succeeded) status code (see [RFC4954](https://datatracker.ietf.org/doc/html/rfc4954)), while *smtp-sink* always responds with a 250 (ok).

    Example with Busybox's sendmail:

    ```sh
    $ sendmail -amPLAIN -auUSERNAME -apPASSWORD -f sender@localhost -S 127.0.0.1:1025 -t -v
    sendmail: recv:'220 smtp-sink ESMTP'
    sendmail: send:'EHLO 2618a41d8d19'
    sendmail: recv:'250-smtp-sink'
    sendmail: recv:'250-PIPELINING'
    sendmail: recv:'250-8BITMIME'
    sendmail: recv:'250-AUTH PLAIN LOGIN'
    sendmail: recv:'250 '
    sendmail: send:'AUTH PLAIN'
    sendmail: recv:'250 2.0.0 Ok'
    sendmail: AUTH PLAIN failed
    ```
- **no SSL/TLS connections**

## see also

- <http://www.postfix.org/smtp-sink.1.html>
- <https://hub.docker.com/r/elchenberg/smtp-sink>
