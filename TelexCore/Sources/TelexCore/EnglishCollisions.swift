// EnglishCollisions.swift — SINH TỰ ĐỘNG bởi gen-english, ĐỪNG SỬA TAY.
// Từ tiếng Anh phổ biến (top-4000) mà Telex mặc định biến thành âm tiết
// Việt hợp lệ (validator không cứu được) — force-restore ở word boundary.
// Bảng là HỢP của lần sinh này với bảng đang ship (xem gen-english: monotone).
// Đã loại các từ mà tiếng Việt thắng (sẽ=sex, ơn=own… — xem gen-english).
// Regenerate:  swift run gen-english google-10000-english.txt 4000 //              Sources/TelexCore/EnglishCollisions.swift
enum EnglishCollisions {
    /// Sorted ascii, lowercase. ~769 từ, tra Set ở boundary (không trên hot path).
    /// Lưu thành MỘT literal (cách nhau bởi space/newline) rồi split lazily ở lần tra
    /// đầu tiên: 1 string literal thay vì 769 phần tử literal → nhỏ hơn hàng
    /// chục KB __TEXT/__DATA. Cùng kiểu với SyllableValidator.rimes.
    // disk/risk/lisk/pisk (19/08/2026): nạn nhân của vần teencode "ik" (thík) —
    // shape i-s-k đọc s thành sắc ra dík/rík hợp lệ oan. Danh sách ĐÓNG, quét đủ
    // /usr/share/dict: mọi -isk còn lại (brisk/frisk/whisk/obelisk…) tự restore vì
    // onset không hợp lệ hoặc từ đa âm. Bảng này thắng validity nên vá ở đây,
    // không phải thu hẹp vần ik.
    static let words: Set<String> = {
        var set = Set<String>(minimumCapacity: 769)
        for token in list.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            set.insert(String(token))
        }
        return set
    }()

    private static let list = """
    access accessed accessible accessing accessories accessory achievements across
    actress address addresses admission admissions advantage advantages affair
    affairs affect affected affecting affects affiliate affiliated affiliates
    affiliation afford affordable aggressive agricultural agriculture aircraft airport
    alabama analysis andorra appropriate architecture arizona arkansas arm
    arms arrange arranged arrangement arrangements array arrest arrested
    arrival arrivals arrive arrived arrives arrow artists arts
    ask aspects ass assault assembled assembly assert asserts
    assess assessed assessing assessment assessments asset assets assign
    assigned assignment assignments assist assistance assistant assisted assists
    associate associated associates association associations assume assumed assumes
    assuming assumption assumptions assurance assure assured atlanta authorized
    avatar awareness bahamas barbara barrel barrier barriers barry
    bars basis bass berry best between bias bits
    bizarre blackberry bless blessed boats border born boss
    boxes brass breasts brussels buffalo buffer business businesses
    busy buys canada canberra cardiff career careers carried
    carrier carriers carries carroll carry carrying cars cases
    cassette cast causes cemetery census character characters charms
    charter charts chassis cherry cherrypick chess chief chosen
    christmas class classes classic classical classics classified classifieds
    classroom cliff coast coffee commission commissioner commissions compressed
    compression congress consistent constitutes consultants contemporary contractor contractors
    controller converter cookbook cordless core corner corporate corporation
    correct corrected correction corrections correctly correlation corruption cost
    costs courses crisis cross crossing crossword cruises currencies
    currency current currently curriculum daddy darkness database databases
    december decided decisions dedicated deemed deeper defend delete
    dense designs dies diff differ difference differences different
    differential differently difficult difficulties difficulty diffs dimensions director
    directories directors directory discounts discuss discussed discussion discussions
    disease diseases disorders displays does donor donors doom
    door doors dose down dress dressed dresses dressing
    dvd dvds earlier earrings effect effective effectively effects
    efficiency efficient efficiently effort efforts element elementary elements
    embassy emission emissions enterprise enterprises ericsson err error
    errors essay essays essence essential essentially essentials essex
    establish established estimates exists expenses explorer express expressed
    expression february ferrari ferry fitness fleece former forward
    fossil freeze furniture further fuss gary gene genes
    genre genres gets ghost gifts glass glasses glossary
    goes gore gossip governor grass greece greene griffin
    gross guess guests guns guys happiness hardcore hardcover
    hardware harris harrison harry her here hire hiss
    honor honors horrible horror horse hose hospitals host
    houses hurricane illness implemented impossible impressed impression impressive
    incorrect increases incurred independent institutions interests interior interracial
    investments irrigation islands issue issued issues jeff jefferson
    jeffrey jerry jesse jessica jesus jewellery kansas karma
    kerry kiss kissing kits laboratory larger larry last
    law laws lesbians less lesser lesson lessons libraries
    library lies life list listings lists literature loans
    lose loss losses madagascar madness major manufacturer maps
    marks marriage married marriott mary mask mass massage
    massive mattress meets melissa mens merry mess message
    messages messaging messenger meters metres mirror mirrors miss
    missed missile missing mission missions mississippi missouri mistress
    mixer moderator more morris morrison moss most motors
    murray must narrative narrow nasa necessary needed needle
    nginx nissan northern nose occurred occurrence occurring off
    offense offensive offer offered offering offerings offers office
    officer officers offices official officially officials offline offset
    offsetof offshore omissions operator operators or order ordered
    ordering orders organization organized outdoor outdoors outlook pair
    pairs para paragraph parameter parameters paris parks particular
    particularly partner partners partnership parts pass passage passed
    passenger passengers passes passing passion passive passport passwd
    password passwords past pasta pays peer peers pens
    per permission permissions perry personals persons pets photos
    physics pieces pierre pins piss pissing plaintiff poems
    poor porn porno ports pose positions possess possession
    possibility possible possibly post posts preferences preferred presents
    press pressed pressing pressure princess process processed processes
    processing processor processors profession professional professor progress progressive
    proposals protocol protocols provisions purposes pussy puts quarter
    questions raw reasons redeem refer reference references referred
    refuse regardless releases remember remembered renaissance represents requests
    researchers residents resistance response responses responsible rest results
    rise risk risks rooms rose russell russia russian sass
    disk lisk pisk
    saw says secretary see seeker seekers seem seemed
    seems sees selected sense sentences september server servers
    session sessions settlement sexo sheffield sheriff sierra sleeve
    soon sorry speeches staff staffing stainless starring statistics
    stderr stress stuff stuffed submission submissions success successful
    successfully suffer suffered suffering sufficient sufficiently suggestions sunglasses
    superior surgery surrey surround surrounded surrounding sussex swiss
    systems tariff task tasks teens temperature temporary tennessee
    term terms terrace terraform terrain terrible territories territory
    terror terrorism terrorist terrorists terry test tests themes
    themselves there these thickness thongs those thousands tier
    ties tiffany tire tires tissue tomorrow tons toolbox
    topless town traffic transactions transferred transmission transsexual trees
    tries trips troops trust turn turns universities unless
    unsubscribe usa uses vary versions verzeichnis vessel vessels
    virus visa visits war warranty wars wax websites
    wireless wisconsin workers writer writers wrong xanax zero
    zoom
    """
}