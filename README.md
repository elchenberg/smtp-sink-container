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

## see also

<http://www.postfix.org/smtp-sink.1.html>
