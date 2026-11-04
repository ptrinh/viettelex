// EnglishFreezePrefixes.swift — SINH TỰ ĐỘNG bởi gen-freeze-prefixes, ĐỪNG SỬA TAY.
// Tiền tố phím thô (chữ thường) mà ở đó một từ tiếng Anh của enlexicon.bin bị live
// spell-check ĐÓNG BĂNG khi đang hiện dấu ("goog" → "gôg"). Eager English restore
// (TelexEngine.eagerEnglishRestore) tra bảng ĐÚNG MỘT LẦN mỗi từ, ở khoảnh khắc đóng
// băng — không bao giờ trên đường nóng mỗi phím.
// 1014 tiền tố từ 2318 từ, dài 4…9.
// Regenerate (từ TelexCore/):
//   swift run -c release gen-freeze-prefixes ../iOS/Keyboard/Resources/enlexicon.bin \
//       Sources/TelexCore/EnglishFreezePrefixes.swift
enum EnglishFreezePrefixes {
    static let minLength = 4
    static let maxLength = 9
    static let count = 1014

    /// Sorted, separated by space/newline. A StaticString lives in the binary's
    /// read-only data: zero heap, nothing built at launch; binary search in place.
    private static let data: StaticString = """
    aaron acac acad affa affe affi affl affo afraid airwa amal aman amass amat amaz anahe anal
    anan anarc anat answe apac apar arab arag arcad archae archai archwa arizo arkan armag armam
    arra arre arri arro artwo asian asiat asks assa asse assi asso assu assy atar awai awak awar
    away awes awful awhi awkw awok axial baff banan bangal barack baranga barnar barr basal
    basis bass batav beeth beetl beforeh benea bened benefi berr bertr bests boasts book bool
    boome boomi boone booste booth booz borou borr boss boston botswa bowed bowel bowie bowin
    bowl bowma buff burr bursts buses canad canal canary capab capac caraca carav carr cartr
    casab cascad cass casts casual catal catast causal cemen cemet cerea cereb ceremo cerr
    charact charr chass chauff cheek cheere cheerful cheeri cheery cheese cherr chess chester
    chests chocol chooses choosin coastal coasts cocoa cocon coeff coff comfort conform confron
    congol consol conson consort conwa cook cool coope coord cornwa corona corone corpor corr
    cosmop cosmos costs coward cowb cuff curr curses dadd damag damasc darr darwin datab datase
    dawne dawson decea decei decem decen decep dedi deduc deed deeme deepe deepl defea defect
    defenc defend defenda defende defendi defense defensi deforest demea demen densel depen
    derek derr descen deserte deserv desper dess detec deten deter dexter diarr diesel diff
    disadv disas discs disdai disks diss disus dodd dodg donov doome doorb doork doorste doorw
    doroth doses dowag downe downfa downh downi downl downri downst downt downw dudl duff dunde
    dvds dwel dwig eeri effe effi effo eject emera emerg emeri emerso enem energe energi energy
    ensem ereb erect ernest erra erro espec essa esse estee eter eurek excee excel excep excer
    excess execu exemp exerci exerti exete expec exped expel expen exper exten exter garag garr
    gasps gauss geel genea genera generi genero genesi genet genev geoff gerr gertr ghanai
    ghosts good goog goss guarant guernsey guerr guess gujarati haral harass harr haryan hass
    hawa hawke hawki hawth haywa heed heel herea hered hereford herei herr hersel herzeg hess
    heter hiss hoff homog homose honol honora honore honori honou hood hook hoope hoov horizo
    horizon hormon horr horses horton hosts howard howel howev howl huawe huff hurr huss ieee
    irra irre irri isaac issu kamal kangaro kansas karachi karate karnat keel keenl keepe keepi
    kernel kerr kiss kosov kuwai lafaye larr lass lasts lausan lawre lawson lawsui lawye leed
    lenses less lester lists locom look loome loomi loope loosel loosene loosened loote looti
    lorenzo lorr loses loss lowel lowered loweri lowl luftwa macar macau manage managi manhat
    marath marian maroon marr masks mass maxwe meeti merced mercen mercer mered merel merr mess
    meteo meter mirr miss mongol monogra monop monot monroe monsoo mood moonl mormon morocc morr
    morton moscow moses moss motor motow muff murr muss naacp nakam naraya narr nasal nascar
    nass natal natash necess need nests niss norfol norr norton norweg norwic norwood noses
    notor notwi nowad nowh nurses oasis oaxaca offe offi offl offs ongoi onwa oriol orion orton
    oswal owed owin owls owne owni oxford pajama panad panam papac papal parace parachu parad
    parag paral parame parami paramo parano parasit parkwa parr pasad pascal pass payab peek
    peel peera peere peeri penet percei percen percep perched perei perenn perfect permea perpen
    perpet perr persecu perspec peter pharaoh pharmac photoc photog photon pierced pierr pieter
    piss poison pool poorer poorl pornogr porou portr poses poss postop posts postwa potom powd
    powel powered powerfu powerh powerl powerp puff purr quarant quarr queensl quieted quieter
    rafae rajasth ramsay recei recen recep recess reed reel reese reev refere referr refresh
    refuel refused refuses reject remed remem renew repea reper repet resched resea resect
    resemb resent reserv respec rested rests resurr reten reused riff rises risks roanok rook
    roomm roone roosev roote roses ross rotor rowin rowl rowspa ruff runwa russ rwand saman
    sarah saraje sarato saraw sarcasm sarcast saskat satan sausag sawmi sawye secess seed seei
    seek seeme seemi seepe seepi semest senec senega sensed sensel senses serena serene sereni
    serpen serr sess siemen sierr softwa songwri soone sooth sorr suff surpr surr suss swal swam
    swanse swap swarm swaye swayi swea swed sweene sweep sweet swel swep swift swig swim swin
    swip swirl swiss swit swiv swol swoope sword swore swun taiwa tanak tariff tasks tasman
    tatar taxab taxati taxpay teena teeth tensed terenc teresa termed terr tested tests texted
    themed themsel theorem theoret therea thereb therefore therei theresa thess thomson thorou
    tiff tiss tomorr took tool tooth topog topol toront torr toss toward towed towel towered
    toweri townl townse townsh townsv traff tramwa transac transat tremen truss trusts turr twel
    twent twic twig twil twin twirl twist twit unwa unwe unwi unwo upwa uses ussr vacan vacat
    variab varian vass veere venet venez vengea verses versus verteb vertex vess vested veter
    vowed vowel wade wadi wafte wage wagn wago waik wail wais wait waiv wake waki wale walk wall
    waln wals walt wand wann want ward ware warfare wari warm warne warni warr warsaw warsh
    warti warwi warwic wash wasp wasps waste wasti watc wate watf watk watso watt wave wavi wavy
    wayn weak weal weap wear weat weav webb webe webs wedd wedg wedn weed week weep weepi wehr
    weig weim weir weis welc weld welf well wels welt wemb wend went wept werew werewol werne
    werner wesl west wester wetl wetn wexfo whal whar what whea whee when wher whet whey whic
    whif whig whil whim whin whip whir whis whit whoe whol whom whor whos wich wick wide wido
    widt wife wifi wiga wigg wigh wiki wilc wild wile wilh wilk will wilm wils wilt wimb winc
    wind wine wing wink winn wins wint wipe wipi wire wisc wisd wise wish wist witc with witn
    wits wive wiza wnba wobb woke wolf wolv woma womb wome wond wont wood wool worce word wore
    work worl worr worse worsened worsh worth woul woun wove wrap wrath wreck wrenc wrest wret
    wrexh wrig wrin wrist writ wrote wroug wrun wryl wuha wwii wyat wyom yemen yerev yester
    zarag zool
    """

    /// True if `raw[0..<n]` (ascii letters, any case) is in the table. Allocation-free.
    static func contains(_ raw: UnsafeBufferPointer<UInt8>, count n: Int) -> Bool {
        guard n >= minLength, n <= maxLength, n <= raw.count else { return false }
        return data.withUTF8Buffer { buf -> Bool in
            @inline(__always) func isSep(_ b: UInt8) -> Bool { b == 0x20 || b == 0x0A }
            var lo = 0, hi = buf.count
            while lo < hi {
                var s = (lo + hi) / 2
                while s > lo, !isSep(buf[s - 1]) { s -= 1 }
                if isSep(buf[s]) {               // landed on a separator run: skip it
                    var t = s
                    while t < hi, isSep(buf[t]) { t += 1 }
                    if t >= hi { hi = s; continue }
                    s = t
                }
                var e = s
                while e < buf.count, !isSep(buf[e]) { e += 1 }
                // Compare token buf[s..<e] with lowercased raw[0..<n].
                var cmp = 0
                var i = 0
                while i < n, s + i < e {
                    var k = raw[i]
                    if k >= 0x41, k <= 0x5A { k |= 0x20 }
                    let b = buf[s + i]
                    if b != k { cmp = b < k ? -1 : 1; break }
                    i += 1
                }
                if cmp == 0 {
                    let tl = e - s
                    if tl == n { return true }
                    cmp = tl < n ? -1 : 1
                }
                if cmp < 0 { lo = e } else { hi = s }
            }
            return false
        }
    }
}
