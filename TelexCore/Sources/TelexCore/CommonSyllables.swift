// CommonSyllables.swift — SINH TỰ ĐỘNG bởi Scripts/gen-common-syllables.py, ĐỪNG SỬA TAY.
// Âm tiết tiếng Việt THƯỜNG GẶP (có dấu), khoá = phím Telex chữ thường, thanh ở cuối
// ("vieetj", "hoaf"). Dùng cho luật viết tắt toàn chữ HOA (TelexEngine.isRareAllCapsAcronym):
// âm tiết hợp lệ mà KHÔNG có trong bảng ⇒ hiếm ⇒ "NAS" là viết tắt, không phải "NÁ".
// Ngưỡng tần suất vnlexicon.bin: ≥ 100 (≤ 3 chữ cái), ≥ 20 (≥ 4 chữ cái).
// 3788 khoá. Chỉ tra ở ranh giới của từ TOÀN CHỮ HOA — không bao giờ trên đường phím.
enum CommonSyllables {
    static let maxKeyLength = 9
    static let count = 3788

    /// Sorted, separated by space/newline. StaticString: read-only data, zero heap.
    private static let data: StaticString = """
    aam aamf aamr aams aan aanr aans aaps aau aaus aays acs af ais aj ams anhr anhs ans aof aor
    aos aps ar as ats awn baacj baamf baamr baams baang baangx baanj baanr baatj baats baauf
    baay baayf baayj baays baayx bachj bachs bacj bacs baf baif baij bais baix baj bams banf
    bangf bangr bangs banhf banhr banhs banj banr bans baof baoj baor baos baox bar bas bats
    baus bawcs bawn bawng bawngf bawngr bawngs bawngx bawns bawps bawts bax bayf bayr bee beechj
    beef beej been beenf beenh beenhf beenhj beens beeps beer bees bef benf bengs bens beos ber
    bes biaf biaj bichj bichs bieecs bieems bieen bieenf bieengs bieenj bieenr bieens bieenx
    bieetj bieets bieeur bieeus bieeux bif bij binhf binhj binhr binhs binhx bir bis bitj bocj
    bocs bof boj bongf bongj bongr bongs bonj bons boocj boocs boof booi booif booij boois booj
    boonf boong boongf boongr boongs boongx boonr boons boor boos bootj bops bor bos botj bow
    bowf bowi bowir bowm bowts buaf buas buf buif buij bumf bunf bungf bungj bungs buoocj buooi
    buooir buoois buooix buoomf buoon buoonf buoong buoongf buootj buoots bups bus buts buwaf
    buwax buwcj buwcs buwj buwng buwngf buwngs buwowcs buwowir buwowm buwowms buwown buwowngs
    buwowu buwowus buwu buyts caam caamf caamr caams caan caanf caangx caanj caanr caapj caaps
    caats caau caauf caauj caaur caaus caay caayj caays cachj cachs cacs caf caif cair cais caix
    camr cams cangf cangr cangs canhf canhj canhr canhs canj canr cans caof caoj caos caps car
    cas cats caus cawm cawms cawn cawnf cawng cawngr cawnj cawns cawpj cawps cawts cayf chaacj
    chaam chaamf chaamj chaamr chaams chaamx chaan chaanf chaanj chaanr chaans chaapj chaaps
    chaatj chaats chaau chaauf chaauj chaaus chaay chaayf chaayr chaays chachj chacj chacs chaf
    chaif chair chais chaix chamf chamj changf changj changr chanhf chanhj chanhr chanhs chanj
    chans chaof chaor chaos chaox chapj char chats chaus chawcj chawcs chawm chawmf chawms chawn
    chawnf chawng chawngf chawngj chawngr chawnj chawnr chawns chawnx chawpj chawps chawtj
    chawts chayf chayj chayr chays chee cheechj cheechs cheem cheemx cheenh cheenhr cheenhs
    chees cheets chef chems chenf chenj chens cheof cheos chepj cheps chetj chets chex chiaf
    chiar chiax chichs chieecs chieem chieems chieen chieenf chieeng chieengf chieenj chieens
    chieeps chieets chieeu chieeuf chieeur chieeus chif chij chimf chims chinhf chinhr chinhs
    chinhx chinr chins chips chir chis chitj chits chiuf chiuj chius choangf choangj choangr
    choangs choans choas choawts chocj chocs choef choej choes choetj choif choij chois chomf
    chomr chongf chongr chongs chongx chonj choocs chooi chooif chooij chooir choois choom
    choomf choon choonf choong choongf choongr choongs choonj choons choopj chootj choots choox
    chops chos chotj chots chowf chowi chowif chowis chowj chowmr chowms chown chownf chowns
    chowpj chowps chowr chows chowtj chuaan chuaanr chuaf chuar chuas chucj chucs chuif chuis
    chuix chumf chumj chums chumx chunf chungf chungr chungs chungx chuoocj chuoocs chuooi
    chuooir chuoois chuooix chuoonf chuoong chuoongf chuoongj chuootj chuoots chupj chur chus
    chutj chuts chuwa chuwaf chuwar chuwas chuwax chuwcj chuwcs chuwf chuwir chuwn chuwng
    chuwngf chuwngr chuwngs chuwngx chuwowcj chuwowcs chuwowmf chuwowng chuwowngf chuwowngr
    chuwowngs chuws chuwx chuyeen chuyeenf chuyeenj chuyeenr chuyeens chuyf cocj cocs cof coif
    coix coj conf congf congj congs congx coo coocs cooi coois coon coonf coong coongf coongj
    coongr coongs coor coos cootj coots coox cor cos cow cowf cowir cowm cowms cown cows cowx
    cuar cucj cucs cuf cuis cuj cumj cums cungf cungj cungr cungs cungx cuns cuoocj cuoocs
    cuooij cuoois cuoomx cuoonf cuoong cuoongf cuoongs cuoonj cuoons cups cur cus cutj cuts cuw
    cuwa cuwar cuwcj cuwj cuwng cuwngs cuwowcj cuwowcs cuwowif cuwowis cuwowix cuwowmf cuwowng
    cuwowngf cuwowngx cuwowps cuwr cuws cuwts cuwuf cuwuj cuwur cuwus cux daam daan daanf daang
    daanx daapj daau daauf daaus daaux daay daayj dachs daif daij dair daj dams danf dangf dangj
    dangs danhf danhs dans daof daoj dawmj dawng dawngf dawngr dawnj dawts dax dayf dayj dayx
    dda ddaam ddaamf ddaamj ddaams ddaamx ddaanf ddaangs ddaapj ddaats ddaau ddaauf ddaauj
    ddaaus ddaay ddaayf ddaayj ddaayr ddaays ddachj ddacj ddaf ddai ddaif ddaij ddais ddaix ddam
    ddamf ddamj ddamr ddams ddan ddanf ddang ddangf ddangr ddangs ddangx ddanh ddanhf ddanhr
    ddanhs ddanj ddao ddaof ddaoj ddaor ddaos ddapj ddaps ddar ddas ddatj ddau ddawcj ddawcs
    ddawms ddawng ddawngf ddawngj ddawngr ddawngs ddawngx ddawnj ddawns ddawps ddawtj ddawts
    ddax ddays dde ddee ddeef ddeej ddeem ddeemj ddeems ddeenf ddeenh ddeenhx ddeens ddeer ddees
    ddeeuf ddef ddem dden ddenf ddeo ddepj dder ddex ddi ddiaj ddiax ddichj ddichs ddieecs
    ddieem ddieemf ddieemr ddieems ddieen ddieenf ddieeng ddieengs ddieenj ddieenr ddieens
    ddieenx ddieepj ddieeu ddieeuf ddieeuj ddieeur ddieeus ddinh ddinhf ddinhj ddinhr ddinhs
    ddinhx ddits ddix ddo ddoaif ddoais ddoan ddoanf ddoangf ddoangr ddoanj ddoanr ddoans ddoatj
    ddocj ddoif ddois ddonf ddong ddongf ddongj ddongr ddongs ddons ddoo ddoocj ddoocs ddoof
    ddooi ddooif ddooij ddooir ddoois ddooj ddoon ddoonf ddoong ddoongf ddoongj ddoongr ddoongs
    ddoonj ddoor ddoos ddootj ddoots ddoox ddor ddos ddowif ddowij ddowis ddown ddowns ddowtj
    ddowx ddu ddua dduaf dduax dducj dducs dduif ddun ddung ddungf ddungj ddungr ddungs ddungx
    dduoocs dduooi dduooir dduoois dduoongs ddur dduwa dduwas dduwcj dduwcs dduwng dduwngf
    dduwngj dduwngs dduwowcj dduwowcs dduwowif dduwowis dduwowmj dduwowng dduwowngf dduwts dee
    deenhf deex deor depj deps dichj dichs dieecj dieecs dieem dieemf dieemj dieemr dieems
    dieemx dieen dieenj dieenr dieens dieenx dieepj dieeps dieetj dieets dieeu dieeuf dieeuj
    dieeur dieeux dif dij dinhf dinhj dinhs dinhx dipj diuj dix doaj doanx docj dof doix dongf
    dongr dongs dongx donj doocs dooif dooij doois doonf doong doongf doongj doots doox dow dowi
    dowif dowr dowx duaanr duaatj ducj duf duj dumf dungf dungj dungs dungx duooix duw duwa
    duwaf duwaj duwj duwng duwngf duwngj duwngr duwngs duwowcj duwowif duwowis duwowng duwowngf
    duwowngj duwowngx duwowtj duwts duwx duyeen duyeenj duyeetj ee eechs eem eps gaamf gaanf
    gaapj gaaps gaatj gaaus gaay gaayf gaayj gachj gacs gaf gaif gais gangf ganhf ganhs gaof
    gaoj gatj gawng gawngj gawngs gawns gawpj gawts gax gays gayx ghee gheenhf ghees ghems gheoj
    gheps ghes ghets ghieecs ghieenf ghimf giaacs giaam giaamj giaams giaamx giaanj giaapj
    giaatj giaauf giaauj giaaus giaay giaayf giaays giaayx giacs giaf giair giaix giamr giams
    gianf giangf giangr giangs gianhf gianr gians gianx giaor giaos giaps giar gias giatj giauf
    giawcj giawcs giawm giawng giawngf giawtj giawts giayf giayx giee gieems gieeng gieengf
    gieengs gieets gieeux giemf gif ginf gioawng gioif gioir gionf giongj giongs gioocs gioon
    gioong gioongf gioongs gioopj gios giotj giow giowf giowif giowis giownx giowr giuaj giuax
    giucj giumf giuoocj giups giuwar giuwax giuwowng giuwowngf giuwtj giuwx gocs gof goij gois
    gonf gongj gongr gonj goocs gooij goois goomf goon goong goongf goox gops gotj gots gowij
    gowir gowms gowx gox gucj guix guoocj guoocs guoongf guwir guwngf guwowm guwowmf guwowng
    guwowngf guwowngj haam haamf haan haangx haanj haaps haauf haauj hachj hachs haf haif haij
    hair hais haix haj hamf hamj hamx hanf hangf hangj hangr hangs hangx hanhf hanhj hanhx hanj
    hans haof haoj haor haos har has hatj hats hawcs hawng hawngf hawngs hawngx hawnr hawns
    hawts hayx heechs heef heej heenh heetj heets heex hef henf henj hepj hets hichj hichs hieem
    hieemf hieemr hieems hieen hieenf hieenj hieenr hieens hieepj hieeps hieetj hieets hieeu
    hieeuf hieeuj hieeur hieeus hinhf hinhr hinhx hits hoachj hoacj hoacs hoaf hoaif hoaij hoair
    hoaj hoanf hoangf hoangr hoanhf hoanhj hoanhr hoanj hoanr hoans hoanx hoar hoas hoatj hoawcj
    hoawcs hoawngf hoawngx hoawts hoays hocj hoets hof hoir hoj honf hongf hongj hongr hongs hoo
    hoocs hoof hooi hooif hooij hoois hooj hoom hoon hoonf hoong hoongf hoongr hoongs hoonx
    hoopj hoor hoos hoots hoox hopj hots howi howix hown howpj howr huaan huaans hueej hueenh
    huees hungf hungs huoongs hutj huts huw huwas huwcs huwng huwngf huwngr huwngs huwngx
    huwowcs huwowng huwowngf huwowngr huwowngs huwowngx huwowu huwu huwux hux huychj huychs
    huyeen huyeenf huyeenj huyeenx huyeetj huyeets huynhf huyr huyts ichs its kee keechj keechs
    keef keej keenh keenhf keer kees keets keeu kemf kems kenf kengr keof keoj keor keos kepj
    keps ker ketj kets kex khaacs khaam khaamr khaams khaanr khaans khaapj khaaps khaats khaau
    khaaur khaaus khaayr khachs khacj khacs khair khais khamr khams khanf khangf khangj khangr
    khangs khanhr khanhs khanr khans khaoj khaor khaos khar khas khats khaus khawcs khawm khawms
    khawn khawng khawngr khawngs khawns khawps khawts kheenh kheenhj kheenhr kheeu kheeuf khenf
    kheos kheps khets khex khiaj khias khichs khieem khieems khieen khieeng khieengx khieenr
    khieens khieeps khieets khieeu khieeus khinhr khir khis khitj khits khoacs khoair khoais
    khoangf khoangr khoangs khoanhr khoanr khoans khoar khoas khoats khoawn khoawngs khoawns
    khoawts khoays khocs khoer khoes khoets khoir khois khomj khoms khoo khoocs khooi khoois
    khoon khoong khoongf khoongj khoongr khoongs khoons khoor khos khowi khowir khowps khuaan
    khuaang khuaanr khuaats khuaay khuaays khucj khucs khuee khueechs khums khungf khungr khuoon
    khuoong khuwas khuwngf khuwngj khuwowcs khuwowng khuwowts khuwowus khuwr khuws khuwu khuwus
    khuyeen khuyeenr khuyeens khuyeets khuyj khuyr khuyuj khuyur kiaf kichj kichs kieem kieemf
    kieemj kieemr kieems kieen kieenf kieeng kieengf kieengr kieengs kieengx kieenj kieenr
    kieens kieeps kieetj kieets kieeu kieeuf kieeuj kieeur kieeus kif kimf kinhf kinhr kinhs
    kins kipj kips kir kis kix kyf kyj kyr kys kyx laam laamf laan laanf laang laanj laans laanx
    laapj laaps laatj laau laauf laauj laay laays laayx lachj lachs lacj laf laij lais laix laj
    lamf lamj lamx lanf langf langj langr langs langx lanhf lanhj lanhr lanhs lanhx laof laos
    laox lapj las latj lats lawcs lawm lawms lawn lawng lawngf lawngj lawngr lawngs lawngx lawnj
    lawpj lawps lax layj lee leechj leechs leef leej leen leenh leenhf leenhj leeuf leex lej
    lengf lengs lens leos ler lex lichj lieecs lieem lieemf lieemj lieems lieemx lieen lieenf
    lieeng lieengj lieengs lieenj lieens lieenx lieepj lieeps lieetj lieeu lieeuf lieeuj lieeux
    linhf linhj linhr linhs linhx lis lits lius loaif loaij loanf loangj loangr loangs loangx
    loanj loatj loats loawng loawngf locj locs loetj loets lof loix loj longf longj longr longs
    longx loo loocj loof looi looij loois looix looj loong loongf loongj loongr loonj loops loos
    lootj loox lotj lots low lowf lowif lowij lownj lowns lowps lowx luaan luaanj luaanr luaatj
    luaj luas lucj lucs luif lunf lungf lungj lungr lungs lungx luoocj luoocs luoomj luoon
    luoonf luoong luoongf luoongs luts luwaf luwaj luwar luwas luwcj luwng luwngf luwngj luwngr
    luwngx luwowcj luwowif luwowis luwowix luwowmf luwowmj luwown luwownf luwowng luwowngf
    luwowngj luwowngx luwownj luwowtj luwowts luwu luwuj luwx lux luyeen luyeenj luyeens luyj
    luyx lys maam maamf maanx maapj maatj maats maau maaux maay maays machj machs macj maf maif
    maij mais maix maj manf mangf mangj mangr mangs mangx manhf manhj manhr manhs manhx manj
    manx maof maoj mas mats mauf maus mawcj mawcs mawng mawngs mawnj mawns mawtj mawts max mayf
    mays mee meechs meemf meenh meenhf meenhj meens meetj mej meof meoj meps mer mets mex michj
    michs mieen mieenf mieeng mieengj mieengr mieengs mieenj mieens mieenx mieetj mieets mieeu
    mieeuf mieeur mieeus mieeux mif mij mimr minhf minhs minj mir mis mix mocj mocs mof moij
    moir monf mongf mongj mongr mongs mons moo moocj moocs moof mooi mooif moois mooix mooj
    moomf moon moong moongf moongj moongs moor mootj moots mor mow mowf mowif mowis mowr mows
    mowx muaf muas mucj muf muif muix muj mungf munj muooi muooif muooij muoois muooix muoon
    muoong muoongs muoongx muoonj muoons muoots muwa muwcj muwcs muwng muwngf muwowi muwowif
    muwowng muwowngf muwownj muwowns muwowps muwowtj muwowts muwu mux myf myx naams naang naangs
    naangx naaps naau naaus naayf naays nachs naij naj nams nanf nangf nangj nangs nanhf nanhj
    nanj nanr naof naos naox napj natj nats nawm nawmf nawms nawn nawng nawngf nawngj nawngs
    nawngx nawps nax nayf nayr nayx neef neems neen neenf neens neeps neer neeu neeus nef nems
    nens nes nets ngaam ngaamf ngaamj ngaamr ngaams ngaamx ngaan ngaanf ngaangr ngaanr ngaans
    ngaapj ngaaps ngaatj ngaats ngaau ngaauf ngaaus ngaaux ngaay ngaayj ngaays ngachj ngachs
    ngacj ngacs ngaif ngaij ngair ngais ngaix ngamf nganf ngangf ngangs nganhf nganhj nganj
    ngans ngaof ngaoj ngaos ngaps ngar ngatj ngats ngawcs ngawm ngawms ngawn ngawns ngawtj
    ngawts ngax ngayf ngays nghee ngheechj ngheechs ngheef ngheej ngheenh ngheeu ngheex nghef
    nghenf nghenj nghens nghenx ngheof ngheox ngher nghes nghetj nghets nghias nghiax nghichj
    nghieem nghieemj nghieemx nghieen nghieenf nghieeng nghieenj nghieens nghieepj nghieetj
    nghieeu nghif nghij nghimr nghinf nghinhx nghir nghitj nghiuj nghix ngoacj ngoacs ngoaif
    ngoaij ngoair ngoais ngoaj ngoamj ngoanhr ngoanj ngoanx ngoawcj ngoawcs ngoawnf ngoawngf
    ngoawtj ngoawts ngoax ngoays ngocj ngocs ngoeof ngoif ngois ngomf ngonf ngongj ngongs ngonj
    ngons ngoo ngoocs ngooi ngooif ngooj ngoon ngoong ngoongx ngoonr ngoons ngoopj ngootj ngos
    ngotj ngots ngow ngowf ngowi ngowif ngowij ngowmj ngowpj ngows ngowts ngowx ngox nguaayj
    nguaayr nguaj ngucj ngueechj nguif nguir nguj ngumj ngunf ngungf ngunr nguooi nguooif
    nguooij nguoonf ngupj ngur ngutj nguts nguw nguwaf nguwaj nguwar nguwas nguwax nguwcj nguwir
    nguwj nguwng nguwngf nguwowcj nguwowcs nguwowi nguwowif nguwowir nguwowis nguwowngj
    nguwowngr nguwowngx nguwu nguwx ngux nguyeen nguyeenf nguyeenj nguyeenr nguyeenx nguyeetj
    nguyj nguyts nhaacs nhaam nhaamf nhaamj nhaamr nhaams nhaan nhaanj nhaanr nhaans nhaanx
    nhaapj nhaaps nhaatj nhaats nhaauj nhaaur nhaay nhaayf nhaayj nhaayr nhaayx nhachs nhacj
    nhacs nhaf nhaif nhaij nhair nhais nhaix nhamf nhamr nhams nhanf nhangf nhangx nhanhf nhanhj
    nhanhr nhanhs nhanj nhanr nhanx nhaof nhaoj nhaos nhaox nhaps nhas nhatj nhats nhauf nhaur
    nhawcs nhawm nhawmf nhawms nhawn nhawnf nhawng nhawngf nhawngj nhawngs nhawnj nhawns nhawnx
    nhawtj nhawts nhax nhayf nhayj nhayr nhays nheechs nheenf nheenj nheeuf nhej nhemf nhemj
    nhemr nhenj nheof nheos nheox nhepj nheps nhes nhetj nhets nhichs nhieecs nhieem nhieemj
    nhieemr nhieemx nhieen nhieenf nhieenj nhieepj nhieeps nhieetj nhieeu nhieeuf nhieeur
    nhieeus nhieeux nhif nhij nhims nhinf nhinhr nhinj nhipj nhips nhir nhis nhits nhius nhix
    nhoaf nhoaif nhoamf nhoangs nhocj nhocs nhoef nhoenr nhoetj nhois nhomf nhomr nhoms nhomx
    nhongx nhonj nhons nhooif nhoois nhoom nhoomr nhoong nhoongf nhoongj nhoonj nhoonr nhoons
    nhoor nhootj nhoots nhops nhor nhotj nhots nhowf nhowif nhown nhownf nhownr nhowps nhowr
    nhows nhowtj nhowts nhowx nhuaanf nhuaanj nhuaj nhuas nhucj nhucs nhueej nhuees nhuif nhuij
    nhuir nhums nhungf nhungs nhungx nhuns nhunx nhuoocs nhuoomj nhuooms nhur nhutj nhuts nhuw
    nhuwaj nhuwcs nhuwn nhuwng nhuwngf nhuwngs nhuwngx nhuwowcj nhuwowng nhuwowngf nhuwowngj
    nhuwowngx nhuwowns nhuwtj nhuwts nhuyeenx nhuyj nichj nichs nieem nieemf nieemj nieen
    nieengf nieets nieeu nieeuj ninhj nir nits noanx nois noj nongf nongj nongs nons noo nooif
    nooij nooir noois nooix nooj noon noong noongf noopj noor noots noox nos nowi nowj nowr nuis
    nuj nungf nungs nungx nuooi nuoois nuoong nuootj nuoots nuts nuwar nuwax nuwcj nuwngj
    nuwowcs nuwowmf nuwowng nuwowngf nuwowngs nuwowpj nuwowus nuwts nuwx oachs oanhs oans ocs oo
    oocs oof ooi oois oom ooms oon oonf oong oongr oongs oonr oor ow owf owi own owr owts pawng
    peenh phaamf phaamr phaan phaanf phaanj phaanr phaans phaanx phaapj phaaps phaatj phaats
    phaaur phaaux phaay phaayr phachj phachs phacj phacs phaif phair phais phamf phamj phanf
    phangf phangr phanj phanr phans phaof phaos phaps phas phatj phats phawcs phawng phawngr
    phawts phee pheen pheenhf phees pheets pheeux phenf phengs pheof pheps phets phias phichj
    phichs phieems phieen phieenf phieenj phieens phieetj phieeu phieeus phif phims phinf phinhf
    phinhr phinhs phis phiuj phocs phomr phongf phongr phongs phoo phoocs phooi phooir phoois
    phoon phoonf phoong phoongf phoongj phoongr phoongx phoor phoos phoots phos photj phowi
    phowis phowts phucj phucs phuf phuir phuj phunf phungf phungj phungs phuns phuoocj phur phus
    phutj phuts phuwcs phuwngf phuwowcs phuwowng phuwowngf phuwowngj phuwowtj quaacs quaan
    quaanf quaangf quaanj quaanr quaans quaanx quaatj quaats quaay quaayf quaayj quaayr quaays
    quaayx quachs quacs quaf quaif quaij quais quanf quangf quangj quangr quangs quangx quanhj
    quanhs quanr quans quaof quar quas quatj quats quauj quawcj quawcs quawn quawnf quawng
    quawngj quawngr quawnj quawns quawpj quawps quawtj quawts quayf quee queen quees queetj
    queets quenf queoj queos quetj quets quis quitj quits quoocs quowis quyeen quyeenf quyeenj
    quyeenr quyeens quyeetj quyeets quyf quynhf quynhs quyr quys quytj quyts quyx raapj raats
    raau rachj rachs racs raf rair raix rangf rangj rangs ranhf ranhr ranhx ranj rans raof raos
    rapj raps rawcs rawng rawngf rawngj rawngr rawns rax reen reer reetj reex remf renf rer rets
    rex richj richs rieeng rieengf rieets rieeu rieeus rinhf rinhr rir rof rongf roo roof rooif
    roois rooix roong roongf roongj roongs roongx roonj roor roots rots rowi rowif rowm rowts
    rowx rox ruaf ruar ruir rungf rungj rungr rungs ruoocs ruooif ruooir ruoongf ruoongj ruoongx
    ruootj rur ruts ruwar ruwcj ruwng ruwngf ruwowcj ruwowcs ruwowif ruwowij ruwowir ruwowis
    ruwowix ruwowmf ruwowms ruwowng ruwowngf ruwowns ruwowtj ruwowuj rux saam saams saan saapj
    saau saauf saaus saays sachj sachs sacj saif sanf sangf sangr sangs sanhf sanhr sanhs sanj
    sanr saos saps sats saus sawcs sawms sawn sawng sawngf sawngs sawngx sawnx sawps sawts secs
    seenh seeps seoj ser sets sex sieeng sieets sieeu sinhf sinhs sir six soaif soais soangj
    soanj soans soatj soats socs soir sois soj songf songs soo soocs sooi soong soongr soongs
    soor soos soots sots sow sowf sowij sowj sowms sown sowr suaats suar sucj sucs sungf sungr
    sungs sungx suoois suoon suoong suoongf suoots supj sups suts suw suwar suwax suwcs suwj
    suwng suwngf suwngr suwngx suwowir suwownf suwowng suwowngj suwowngs suwowtj suwowts suwr
    suws suwu suyeenr suyeenx suyts syx taam taamf taams taan taanf taang taangf taanj taans
    taapj taaps taatj taats taauf taaur taay taayr tachj tachs tacs taf taif taij tair tais taj
    tamj tams tanf tangf tangj tangr tangs tanhf tanhj tanhs tanr tans taof taoj taos tapj tar
    tas tats tauf tawcj tawcs tawm tawms tawng tawngf tawngj tawts tax tee teechs teef teej teen
    teenh teenhx teepj teer tees teets tef ter tes thaam thaamf thaamj thaamr thaams thaamx
    thaan thaanf thaanj thaanr thaanx thaapj thaaps thaatj thaats thaau thaauf thaaus thaay
    thaayf thaayr thaays thachj thachs thacj thacs thaf thair thais thaix thamr thams thangf
    thangr thangs thanhf thanhj thanhr thanhs thanr thans thaof thaoj thaor thaos thaps thar
    thatj thats thawcs thawm thawmr thawms thawn thawnf thawng thawngf thawngj thawngr thawngs
    thawns thawps thawts thayf thayr thays thee theechs theef theem theemf theenh theeps theer
    thees theets theeu theeuf themf thenf thenj theoj theps ther thets thiaf thias thichj thichs
    thieecs thieem thieemf thieemr thieen thieenf thieeng thieenj thieenr thieens thieepj
    thieeps thieetj thieets thieeu thieeuf thieeuj thieeur thieeus thif thij thims thinf thinhf
    thinhj thinhr thinhs this thitj thits thiur thoaij thoair thoais thoanf thoangr thoangs
    thoans thoar thoas thoatj thoats thoawn thoawngs thoawts thoax thocj thocs thoif thoir thois
    thoj thomr thongf thongx thoo thoocs thooi thooir thoois thoon thoong thoongs thoonr thoons
    thoor thoots thops thor thotj thots thow thowf thowi thowif thowis thowj thowm thowms thowr
    thowts thuaan thuaanf thuaanj thuaanr thuaans thuaanx thuaatj thuaf thuar thucj thucs thuee
    thuees thuf thuir thuis thuj thungf thungj thungr thungs thungx thuoocj thuoocs thuoomj
    thuoon thuoongf thuootj thuowr thupj thur thus thutj thuts thuw thuwa thuwaf thuwar thuwcj
    thuwcs thuwj thuwngf thuwngx thuwowcj thuwowcs thuwownf thuwowng thuwowngf thuwowngj
    thuwowngr thuwowngs thuwowtj thuwowts thuwr thuws thuwus thuyeen thuyeenf thuyeets thuyf
    thuyj thuyr thuys tiar tichj tichs tieecj tieecs tieem tieemf tieemj tieems tieen tieenf
    tieeng tieengs tieengx tieenj tieenr tieens tieenx tieepj tieeps tieetj tieets tieeu tieeuf
    tieeur tieeus tieeux tij timf tims tinhf tinhj tinhr tinhs tinhx tins tir tis toacj toacs
    toaf toaij toais toaj toanf toangf toangs toanr toans toar toats tocs toetj toets tof toir
    toms tongf tongj tongr too toocj toocs tooi tooif tooij toois toom toon toonf toong toongf
    toongr toongs toonr toons toor toos toots tor tow towf towis towmr tows traam traamf traamx
    traan traanf traanj traans traapj traatj traau traauf traaur traaus traayf traayr trachj
    trachs tracj tracs traf traij trair trais traix tramf tramj tramr trams tranf trangf trangj
    trangr trangs tranhf tranhs trans traof traoj traor traos traps trar tras trats trawcj
    trawcs trawm trawmf trawms trawn trawnf trawng trawngf trawngs trayr treen treenr treetj
    treeu treeuj treex trenx treof treoj treor treos trer trets triaj trichj trichs trieenf
    trieenj trieenr trieenx trieetj trieets trieeu trieeuf trieeuj trif trij trinhf trinhj
    trinhx tris triuf triux trix trocj trocs trof troij trois troj tronf trongf trongj trongr
    tronj trooi trooif trooij troois trooix troom troomj troon troong troongf troongs troonj
    troons trotj trots trowi trowif trowj trown trownj trowns trowr trowtj trowts truaan truaatj
    truaats trucj trucs truij truj trumf trunf trungf trungj trungs trungx truoong truoongf trus
    truts truwa truwcj truwf truwng truwngf truwngs truwowcj truwowcs truwownf truwowng
    truwowngf truwowngj truwowngr truwowngs truwowtj truwuf truwx truyeen truyeenf truyeenj
    truyeenr truyj tuaan tuaanf tuaans tuaanx tuaats tucj tucs tueechs tueej tuf tuij tuis tuj
    tungf tungj tungs tuoocj tuoocs tuooi tuooir tuoois tuoon tuoonf tuoong tuoongf tuootj
    tuoots tur tus tuw tuwaj tuwcs tuwf tuwj tuwng tuwngf tuwngr tuwowcj tuwowcs tuwowi tuwowir
    tuwowis tuwowm tuwowng tuwowngf tuwowngj tuwowngr tuwowngs tuwr tuws tuwuj tuyeen tuyeenf
    tuyeenr tuyeens tuyeetj tuyeets tuyf tuyps tuys tuyts tyr tys uar ucs uf uir ungr uoong
    uoongr uoongs uoons ups ur uts uw uwa uwcs uwf uwng uwngs uwowcs uwowng uwowngf uwowngr
    uwowts uwu uyeen uyeenr uynhs uyr uys vaan vaanf vaang vaangf vaanj vaanr vaans vaanx vaaps
    vaatj vaats vaay vaayf vaayj vaayx vachj vachs vacs vaf vaif vair vaix vangf vangj vangr
    vangs vangx vanhf vanhs vanhx vanj vans vanx vaof var vas vatj vawcs vawn vawng vawngf
    vawngr vawngs vawnj vawtj vawts vax vays veef veej veenh veenhr veets venj ver ves vex vichs
    vieecj vieem vieen vieenf vieeng vieengs vieenj vieenr vieenx vieetj vieets vif vij vinhj
    vinhx vis vitj vix vocs voif vongf vongj vongx voo voocj vooij voong voongf voons voox vor
    vowf vowif vowis vowj vowr vows vowtj vowx vox vuj vungf vungj vungx vunj vuoong vuootj
    vuoots vus vuwaf vuwcj vuwngf vuwngj vuwngx vuwowcj vuwown vuwownf vuwowng vuwowngj vuwowngr
    vuwowngs vuwownj vuwowtj vuwts vux xaam xaaus xaay xachs xacs xaf xaif xaj xams xaof xaor
    xar xas xawm xawng xawngf xawns xax xayr xeechj xeechs xeenh xeeps xees xengf xengr xeor xes
    xets xichj xichs xieecs xieem xieen xieengf xieenr xieets xieeu xif xinhf xinhr xinhs xinhx
    xinj xinr xir xis xitj xiur xius xoachj xoacj xoaif xoanf xoangf xoangr xoanhf xoas xoawn
    xoawns xoays xocs xoetj xoms xoo xooi xoong xoongr xoonj xoor xots xow xuaan xuaanr xuaats
    xucs xungs xuooi xuoong xuoongf xuoongs xuoots xuwa xuwng xuwngr xuwngs xuwowcj xuwowcs
    xuwowng xuwowngr xuwowngs xuwowts xuwr xuws xuyeen xuyeens xuyeets xuyts yeemr yeems yeen
    yeeng yeengr yeens yeets yeeu yeeus ys
    """

    /// True if `key[0..<n]` (lowercase ascii Telex keys) is in the table. Allocation-free.
    static func contains(_ key: UnsafeMutableBufferPointer<UInt8>, count n: Int) -> Bool {
        guard n >= 1, n <= maxKeyLength else { return false }
        return data.withUTF8Buffer { buf -> Bool in
            @inline(__always) func isSep(_ b: UInt8) -> Bool { b == 0x20 || b == 0x0A }
            var lo = 0, hi = buf.count
            while lo < hi {
                var s = (lo + hi) / 2
                while s > lo, !isSep(buf[s - 1]) { s -= 1 }
                if isSep(buf[s]) {
                    var t = s
                    while t < hi, isSep(buf[t]) { t += 1 }
                    if t >= hi { hi = s; continue }
                    s = t
                }
                var e = s
                while e < buf.count, !isSep(buf[e]) { e += 1 }
                var cmp = 0
                var i = 0
                while i < n, s + i < e {
                    let k = key[i]
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
