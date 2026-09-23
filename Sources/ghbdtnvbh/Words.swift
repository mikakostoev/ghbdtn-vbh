/// Words the system dictionaries don't know, so "лгиусед" still becomes "kubectl" and "ahjyntyl" becomes "фронтенд".
/// Seed only: the long tail is learned per user from manual converts (words.txt).
/// Every word here must pass the collision check in selfTest(): its reading in the other layout must not be
/// a dictionary word, or adding it would stop that word from being fixed ("jq" reads "ой", "vtk" reads "мел").
/// The dictionary can't see every collision — "vue" is left out by hand because it reads "мгу".
// ponytail: exact forms only ("дебажить" but not "дебажу"); learning covers the forms a user actually types.
/// The app's own name. macOS files the names of installed apps into the personal lexicon its speller consults
/// (LaunchServices -> IntelligencePlatform -> AppleSpell), so on a Mac with the app installed "ghbdtn" and "vbh"
/// pass as words in every language and the headline example would never switch. The speller is not asked about them.
let ownName: Set<String> = ["ghbdtn", "vbh"]

let extraWords: [String: Set<String>] = [
    "en": words("""
        aac aliexpress antd api archlinux argparse asciidoctor asciinema async asyncio aws awscli azcopy backend
        bcrypt bgp binutils bmw bose browserify bybit cdn certbot claude cli config coreutils csv curl dao dbus
        deno diffutils django dji dnsmasq docker dota dpkg dribbble dts dynamodb dyson env etcd exiftool fastapi
        ffmpeg findutils fontconfig foundationdb frontend fzf gedit ghidra github gitlab gitleaks gnuplot
        gosuslugi gpt grafana graphql graphviz grep habr harfbuzz hevc htop httpie hunspell imagemagick ios jbl
        js jsdoc json jupyterlab jwt kotlin kubectl kubernetes lazygit leiningen localhost lsof lsusb lte lua
        luajit lyft mathjax memcached mkcert mkvtoolnix mpv mri mysqldump neofetch netcat netlify nginx nmap
        nodemon nosql npm npx nuxt nvim ocaml oled onnxruntime opencv openfortivpn openjdk openldap
        openstackclient openvpn orm otp phpmyadmin phpunit pkce pnpm postgres protobuf pycharm pyinstaller
        pymongo pyqt qr rabbitmq redis regex regexp repo rethinkdb rocksdb scss sdk semgrep sennheiser sha
        sqlalchemy sqlmap sre ssh sudo svg systemctl texlive tidb tinymce tldr tls tmux uikit uri usbc usdt utf
        valgrind vapoursynth venv vercel verilator vga viber virtualenv vite vk vpn wasm wasmtime webpack
        whatsapp wix wma wxwidgets xcode xiaomi yaml zlib zsh zstd
        """).union(words("""
        ama amd apk asus atm bbc bdd bsd cet cfo chf cia cio cmake cnn cors cpc crm csharp csrf cto dba devops
        dhcp diy dylib eks erp eslint eur faq fbi fft fifa flac gbp gcp gmt gps gradle grpc gui hdmi iam ibm
        imap ioc iot ipa ipo jdk jpy jsx jvm khz kpi macos mfa mhz mqtt msi mvp nda nfc nfl ngl nhl nsa ntp
        nvidia nvme oauth ocr okr oop pcie pcm pkg poc rar rdp rds rfc rgb risc roi rsa saas saml sata sem seo
        sla sns sqs ssid sso tcpip tdd toml tsx ttl tui uae udp uefa uefi usa usd utc vpc wpa xss yml
        """)),
    "ru": words("""
        баг бэк кэш бд хах ахах
        апрувнуть бэкенд бэкенда бэкенде вайлдберриз вебворкер вебсокет гугл датасеты дебажить дискорд кринж
        кринжово кста ллм маршрутизаторами мерж пжл пипелайн поды пулл пулреквест ревьюэр релизнуть роадмап
        спотифай стейдж темплейт тикток тимлид тулзы файнтюн фейловер фронтенд фуллстэк чатгпт энвайронмент
        эндпоинт
        """).union(words("""
        апи апк асутп аэс бик бмп брикс бти бтр ввц вгик вднх вмф внп втб втэк вшэ гаи гдр гибдд гис гмо гпк гру
        грэс гсм гто гум гэс двфу дкб днк дпс егаис егрип егрн егрюл егэ екб енвд есхн жкт жкх зао зож зпт зсд
        инн ипц итмо каско кбк ккт кнд кндр кнр коап кпк кпп кпрф кпэ кст кфу кхл лвс лдпр лфк лэп магатэ мвф
        мгимо мгту мид мифи мкад мкс мпгу мрот мрп мрт мрэо мсфо мфти мфц мхат мэи нато нба нгу ндпи ндс ндфл
        нзч нии ниокр нко нло нмц нпд нск нхл оао оаэ овд огрн огэ озу окб оквэд окпо омг оон ооп опс орви осаго
        осно офд офз пао пбу пво пдд пжл пнд ппр псн птс пту пфдо ргб ргсу ржд ркн рко рнк ровд рпг рпл рпц рсбу
        рсв рсфср рувд рудн рфс рэу сбп сдэк сзв сзвм скр скуд сми смп снг снилс снип снп снт соэ спбгу спид сро
        ссср ссуз субд сфр сша тгу тсж тэо тэц уефа упк урфу усн фап фбр фгис фнс фрг фсин фскн фсо ффд цик цкад
        цнс црб цру цска цум эвм экг эцп ээг юнеско юфу
        """)),
]

/// Protect-only: left alone when typed, but never a reason to switch to. Two-letter abbreviations and the ones
/// whose other reading means something too ("рф" reads "ha", "зп" reads "pg").
let protectedWords: [String: Set<String>] = [
    "en": words("""
        ar ba ceo ci ec ecs gg ghz gz hz ide jre lg md nba py qa rb tb ts ufc ux vr wp
        """),
    "ru": words("""
        ао афк бд ввп ввс вдв вк гк гкб двс ддс дз дк дмс дтп ес ефс жд жк зк зп ии ип ит квн кгб кт лс мвд мг
        мгу ммс мсэ мтс мфу мчс нг нк омс пвз пж пк пфр рб рк рф ск смс спб сфу тг тз тц увд ук упд фк фл фсб
        фсс фтс хк цб цгб цп чд чп чс чсв
        """),
]

/// Kept although the other reading is a real word: breaking "vk" into "мл" is worse than not fixing "мл".
let deliberateCollisions: Set<String> = ["vk", "tls"]

private func words(_ text: String) -> Set<String> { Set(text.split(whereSeparator: \.isWhitespace).map(String.init)) }
