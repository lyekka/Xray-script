# Xray-REALITY управляющий скрипт

* Скрипт управления REALITY, написанный на чистом Shell
* Использует конфигурацию VLESS-XTLS-uTLS-REALITY
* Автоматическое заполнение портов прослушивания xray
* Возможность ввода пользовательского UUID; нестандартный UUID преобразуется в UUIDv5 с помощью `Xray uuid -i "пользовательская строка"`
* Возможность выбора и ввода dest
  * Проверка TLSv1.3 и H2 для введенного dest
  * Автоматическое получение serverNames для введенного dest
  * Фильтрация wildcard-доменов и CDN SNI-доменов в автоматически полученных serverNames; если dest является поддоменом, он автоматически добавляется в serverNames
  * Пользовательское отображение spiderX для введенного dest, например: при вводе dest `fmovies.to/home` в конфигурации клиента будет отображаться `spiderX: /home`
* Запрет трафика в Китай, рекламы и bt по умолчанию
* Возможность развертывания Cloudflare WARP Proxy с помощью Docker
* Автоматическое обновление geo-файлов

## Проблема

Несмотря на использование WARP для доступа к OpenAI, войти в систему не удается.

Друг из США проверил: тот же аккаунт у него работает, а у меня выдает ошибку и требует связаться с администратором. Возможно, проблема в IP.

Для нормального доступа и входа рекомендуется не использовать эту функцию, а воспользоваться скриптом [WARP 一键脚本][fscarmen] для получения рабочего IP, затем изменить `/usr/local/etc/xray/config.json` согласно [методу разделения трафика на WARP Client Proxy][fscarmen-warpproxy].

## Как использовать

* wget

  ```sh
  wget --no-check-certificate -O ${HOME}/Xray-script.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/reality.sh && bash ${HOME}/Xray-script.sh
  ```

* curl

  ```sh
  curl -fsSL -o ${HOME}/Xray-script.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/reality.sh && bash ${HOME}/Xray-script.sh
  ```

## Интерфейс скрипта

```sh
--------------- Xray-script ---------------
 Version      : v2023-03-15(beta)
 Description  : Скрипт управления Xray
----------------- Управление загрузкой ----------------
1. Установить
2. Обновить
3. Удалить
----------------- Управление операциями ----------------
4. Запустить
5. Остановить
6. Перезапустить
----------------- Управление конфигурацией ----------------
101. Просмотреть конфигурацию
102. Статистика
103. Изменить id
104. Изменить dest
105. Изменить x25519 key
106. Изменить shortIds
107. Изменить порт прослушивания xray
108. Обновить существующие shortIds
109. Добавить пользовательские shortIds
110. Использовать WARP для разделения трафика (доступ к OpenAI)
----------------- Другие опции ----------------
201. Обновить до последней стабильной версии ядра
202. Удалить лишние ядра
203. Изменить порт SSH
204. Оптимизация сетевого подключения
-------------------------------------------
```

## Конфигурация клиента

| Название           | Значение                                    |
| :----------------- | :------------------------------------------ |
| Адрес              | IP или домен сервера                        |
| Порт               | 443                                         |
| ID пользователя    | xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx        |
| Управление потоком | xtls-rprx-vision                            |
| Протокол           | tcp                                         |
| Безопасность       | reality                                     |
| SNI                | learn.microsoft.com                         |
| Fingerprint        | chrome                                      |
| PublicKey          | wC-8O2vI-7OmVq4TVNBA57V_g4tMDM7jRXkcBYGMYFw |
| shortId            | 6ba85179e30d4fc2                            |
| spiderX            | /                                           |

## Благодарности

[Xray-core][Xray-core]

[REALITY][REALITY]

[chika0801 Xray 配置文件模板][chika0801-Xray-examples]

[部署 Cloudflare WARP Proxy][haoel]

[cloudflare-warp 镜像][e7h4n]

[WARP 一键脚本][fscarmen]

**Этот скрипт предназначен только для обучения. Не используйте его для незаконных действий. Интернет не является зоной вне закона.**

[Xray-core]: https://github.com/XTLS/Xray-core (THE NEXT FUTURE)
[REALITY]: https://github.com/XTLS/REALITY (THE NEXT FUTURE)
[chika0801-Xray-examples]: https://github.com/chika0801/Xray-examples (chika0801 Xray 配置文件模板)
[haoel]: https://github.com/haoel/haoel.github.io#943-docker-%E4%BB%A3%E7%90%86 (使用 Docker 快速部署 Cloudflare WARP Proxy)
[e7h4n]: https://github.com/e7h4n/cloudflare-warp (cloudflare-warp 镜像)
[fscarmen]: https://github.com/fscarmen/warp (WARP 一键脚本)
[fscarmen-warpproxy]: https://github.com/fscarmen/warp/blob/main/README.md#Netflix-%E5%88%86%E6%B5%81%E5%88%B0-WARP-Client-ProxyWireProxy-%E7%9A%84%E6%96%B9%E6%B3%95 (Netflix 分流到 WARP Client Proxy、WireProxy 的方法)
