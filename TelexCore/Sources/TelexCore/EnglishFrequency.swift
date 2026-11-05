// EnglishFrequency.swift — SINH TỰ ĐỘNG bởi Scripts/gen-english-frequency.py, ĐỪNG SỬA TAY.
// Tần suất tiếng Anh (enlexicon.bin) và tiếng Việt (vnlexicon.bin, âm tiết Telex gõ ra từ cùng phím) trên
// CÙNG thang log 0–255 (gấp 10 lần ≈ 45 byte) + cặp âm tiết Việt hay đi liền (vnlm.bin). Số liệu thống kê
// suy ra từ dữ liệu CC BY-SA 4.0 / CC BY 3.0 / CC BY 2.0 FR — ghi công: docs/DATA-SOURCES.md mục
// "EnglishFrequency.swift". Chỉ tra ở RANH GIỚI từ (luật tần suất, lật lại, từ Anh mạnh của sửa ngược).
// 1585 từ (548 trùng âm tiết Việt, 1037 từ mạnh en ≥ 150), 699 cặp.
enum EnglishFrequency {
    static let strongMin: UInt8 = 150
    static let maxWordLength = 14
    static let maxPairLength = 15
    static let wordCount = 1585
    static let pairCount = 699

    /// "từ=EEVV" (EE = tần suất Anh, VV = tần suất Việt, hex), sắp theo từ. StaticString: dữ liệu chỉ
    /// đọc trong binary, không heap, không dựng gì lúc chạy.
    private static let words: StaticString = """
    able=a900 about=d300 above=a400 access=9900 according=9f00 account=9b00 across=b100 act=a400
    action=a100 activities=9a00 activity=9b00 actually=a300 added=9e00 addition=9900
    additional=9600 afar=5b01 afraid=9e00 after=c500 afternoon=9900 again=c400 against=b800
    age=a100 ago=a500 agreed=9700 ahead=9900 air=ac55 airs=6387 ais=4687 ajar=5b01 ajax=5e01
    alive=9600 all=d800 almost=b100 alone=a900 along=ae00 already=b100 also=c300 although=a800
    always=b700 america=9700 american=a800 among=a700 amount=9900 amp=b200 ams=408c ana=6c84
    analysis=a400 and=ff00 angeles=9800 angry=9600 another=bb00 answer=a400 answered=a000
    any=c300 anyone=a800 anything=b700 anyway=9d00 appeared=9f00 application=9800 approach=a100
    are=d900 area=a300 areas=9a00 arm=aa4f arms=ae8c around=c300 arrived=9c00 art=9b00 arts=8165
    as=e599 asa=5901 asked=c100 asp=46a3 associated=9c00 attention=a100 aura=695b available=a100
    away=c200 ax=5b5c axis=7d87 baby=a100 back=d200 bad=a800 bag=9a00 baja=5d01 bans=54ac
    bar=966a barely=9600 bari=562b barn=81c1 bars=7b85 based=ac00 basic=9600 basis=9600
    bats=5889 bays=6b0c beautiful=a200 became=a000 because=be00 become=a600 bed=af00
    bedroom=9600 bee=6883 beef=6c88 been=d2bd beer=8a7d beers=5e74 bees=6274 before=c800
    began=af00 beginning=9600 behavior=9800 behind=b600 being=ba00 believe=ac00 below=9900
    beneath=9c00 bern=6101 beside=a100 best=ad5f better=b300 between=bc00 beyond=9c00 bias=7601
    big=ae00 bins=4201 bit=a900 bits=784a black=ae00 blood=a600 blue=a500 boast=5801 boats=7701
    body=b300 boer=5d01 bois=5562 bono=544d book=a800 books=9800 boom=6914 boost=635e boots=8b5e
    bore=7c01 boris=6c62 born=9101 bose=5501 bosom=6d01 both=b700 bow=8579 bows=663f box=993f
    boxer=7001 boxers=5901 boxes=7e01 boy=aa00 boys=9a00 break=9a00 breath=a800 bright=9800
    bring=a200 british=9900 broke=9800 broken=9900 brother=a700 brought=a900 brown=9900
    building=9d00 burn=8139 burns=6c5d burst=8d8c bury=6c01 bus=8573 business=a800 bust=628c
    busy=9301 but=e300 buys=5301 bwf=5c01 caf=57a1 call=ae00 called=b000 came=be00 cams=3ea0
    cans=6679 capital=9600 caps=5e78 captain=9b00 car=add1 care=a800 carried=9800 cars=87b2
    carts=5e83 cary=5701 casa=6401 case=b000 cases=9f00 cast=8c83 catch=9600 cats=7383
    caught=a400 cause=9b00 cell=9c00 cells=9a00 center=9900 central=9a00 century=a000
    certain=a100 certainly=9b00 chair=a46d chairs=852c championship=ab00 championships=9f00
    chance=a200 change=ab00 changed=9b00 changes=9e00 chaos=7671 chapter=ad00 char=4c9c
    charles=9f00 charm=7901 charms=6208 charts=6756 check=9700 cheer=6f01 cheers=65a8 chef=656b
    chest=a342 chicago=9800 child=a600 children=ad00 china=9600 chips=6c48 choir=5e04
    choirs=5567 chores=642e chose=842e chosen=8601 church=9e00 cis=5901 city=a400 class=a000
    clear=a100 clearly=9600 close=ac00 closed=a500 closer=9c00 clothes=9c00 coast=8301
    coats=6a01 coffee=9d00 cold=a500 come=c200 comes=9900 coming=ac00 common=a300 community=a100
    como=570f company=a200 competed=9800 complete=9700 completely=9900 complex=9700
    conditions=9e00 congo=75ce congress=9800 cons=3e2a consider=9900 considered=9d00
    content=9b00 context=9800 continued=a300 control=a900 conversation=9b00 cops=7b3d core=8b01
    cores=5501 corn=743f corner=9e00 corps=753d cost=9b49 could=d600 countries=9b00 country=a200
    couple=a100 course=b000 court=a100 covered=9a00 cow=72c2 cows=6a78 cox=7030 create=9800
    cried=9b00 critical=9600 cross=9600 cultural=9a00 culture=9c00 cups=7675 current=9d00
    cut=a100 cuts=707c dad=a3a0 dais=584e dams=639b dana=64b2 dans=4d7d dar=5c44 dark=ae00
    darkness=9600 darts=5e40 das=6e01 data=ae00 daughter=a000 david=a100 dawn=8601 days=ad3b
    dead=a900 deal=9c00 dear=9e00 death=a600 debut=a500 decided=a100 decision=9b00 dee=656c
    deed=6a73 deeds=6990 deep=a900 deer=704b def=5a61 defend=7684 dense=6f34 department=9800
    der=845a des=8901 described=9900 design=9d00 desk=9b00 developed=9800 development=aa00
    did=d7e5 die=9e00 died=9d00 difference=9600 different=b200 difficult=9a00 dinner=9d00
    direct=9600 direction=9800 dis=6c5a disambiguation=9a00 disease=9a00 distance=9900
    doctor=9d00 does=b601 dog=9b00 doing=ae00 done=b100 donor=6c01 donors=6301 dons=5001
    doom=6001 door=be01 doors=9501 dora=5701 doris=5d01 dorm=5b4f dorset=6401 dos=6d4c dose=8001
    dots=5e01 doubt=9b00 dow=5668 down=cc17 downs=6b1c dress=9900 dressed=9600 drew=9b00
    drink=9b00 drive=9800 dropped=9d00 due=a100 during=b000 dust=8b06 dwarf=6273 each=b700
    ear=9600 earlier=9700 early=a700 earth=9d00 east=9600 easy=9d00 eat=9a00 economic=a200
    edge=9b00 education=a300 effect=a100 effective=9700 effects=9d00 either=a700 else=af00
    empty=9b00 ems=4e2c end=b000 energy=a200 english=a000 enough=b700 entered=9800 entire=9700
    environment=9800 eos=445a eps=5c8e er=7a01 ere=6901 especially=9f00 est=6529 european=9800
    even=c600 evening=a000 events=9700 ever=b600 every=b700 everyone=a800 everything=b100
    evidence=a000 ex=7e01 exactly=a000 example=ae00 except=9d00 expected=9900 experience=a300
    expression=9c00 eye=a300 eyes=c600 face=c100 fact=a800 factors=9800 fall=9b00 family=af00
    far=b100 fast=9c00 father=b700 fear=a000 feel=b300 feeling=a900 feet=ad00 fell=a400
    felt=bc00 few=b900 field=9f00 fight=9a00 figure=ac00 filled=9f00 final=9700 finally=a800
    financial=9a00 find=b700 fine=a600 finger=9800 fingers=a700 finished=9b00 fire=a700
    first=c100 five=a800 floor=aa00 florida=9600 focus=9800 follow=9800 followed=a400
    following=a900 food=a100 foot=9b00 for=e600 force=9d00 foreign=9800 forget=9700 form=a900
    forms=9800 forward=a600 found=b700 four=a800 free=a300 french=9600 friend=ab00 friends=a700
    from=db00 front=b200 full=a900 function=a000 further=a400 future=a000 gaa=5e01 gaan=5a61
    game=9700 gangs=5d01 gaps=6c4a gary=7e3f gas=8f2e gasp=764a gave=b200 gays=4567 gaze=a000
    gems=5601 gene=8401 general=aa00 generally=9700 genes=7c01 genre=6f01 genres=5f01
    gently=9600 george=a400 get=c900 gets=9101 getting=ab00 ghana=7701 ghost=8401 gifts=7601
    girl=b000 girls=9e00 giro=5663 give=b300 given=ab00 giving=9b00 glad=9a00 glanced=a000
    glass=a200 global=9800 goats=5e01 god=b100 goes=9301 going=c400 gold=9700 gone=ae00
    good=c400 gore=6201 got=c000 government=a800 gown=8001 gowns=5e01 grabbed=9b00 great=b400
    greater=9900 green=9f00 grew=9600 ground=a600 group=aa00 groups=9e00 growth=9b00 guns=8101
    gus=5b3d gust=6050 guts=6a50 guys=9601 haar=7501 haas=5501 had=e700 hair=b199 hairs=6a75
    half=ad00 hall=9c00 hamas=5801 hand=c200 hands=b900 hangar=5901 hangs=6349 hans=6a7c
    happen=9b00 happened=aa00 happy=a500 hard=b100 hari=5399 harm=8401 has=c86c hasan=614c
    hast=64a3 hats=6ba3 have=dd00 having=ac00 hawks=6b01 hays=5120 head=c300 headed=9800
    health=a700 hear=ad00 heard=b400 heart=b100 heavy=9b00 held=ae00 hell=a300 help=b400
    henry=9c00 her=f001 here=c763 hero=7f4c hers=9860 herself=b300 high=b000 higher=9e00
    himself=b900 hips=8b37 his=ed57 history=a700 hit=9e00 hits=6c7f hold=a400 holding=a000
    home=b800 homo=54bb honor=8551 honors=8101 hope=a700 horn=7523 horns=6801 horse=9c01
    hose=6101 host=8465 hot=a000 hour=a200 hours=a300 house=b900 how=ca46 however=b300 huge=9600
    human=ac00 hundred=9e00 hurt=a000 hurts=6f9f husband=a100 huts=5c9f idea=a900 if=d64a
    image=9900 immediately=9c00 impact=9700 important=ac00 include=9e00 including=a500
    increase=9b00 increased=9800 indeed=9b00 individual=a100 individuals=9700 influence=9700
    information=af00 ins=4f22 inside=b000 instead=a300 institute=a100 interest=a000
    international=a600 into=d200 involved=9800 ira=6945 irene=6301 is=e85e isa=5b01 issue=9700
    issues=9b00 ist=5daf isu=5701 its=c2af itself=a000 james=a500 jesus=9a00 job=a200 john=b400
    joseph=9600 journal=a000 just=cf00 keen=781c keep=b200 keeps=7e53 kept=a900 kern=5301
    key=9c00 kids=9800 kill=9e00 killed=9c00 kind=ad00 king=a200 kitchen=a200 kits=5f36
    knees=9600 knew=be00 know=ce00 knowing=9a00 knowledge=a200 known=a500 knows=9d00 kris=5701
    lady=a600 lama=5c8e lamar=5c5b land=a000 language=a200 laos=6467 laps=6f34 lara=5b01
    large=a900 lars=5ca0 las=82a0 last=ba8d late=a200 later=ac00 laugh=9900 laughed=a400
    laura=755e law=ac01 lawn=787a laws=9001 lays=5942 lead=9800 leaned=9e00 learning=a200
    least=ac00 leave=ae00 leaving=a000 led=9c00 lee=928e left=bb00 legal=9800 legs=a000
    lens=7278 les=7e36 lest=6d58 let=bf00 lets=7058 letter=9800 level=a700 levels=9900 lex=56b5
    liar=6c01 life=bc00 lifted=9b00 lifts=686c light=b000 like=d300 liked=9a00 likely=9d00
    limited=9600 line=a400 lips=a935 lisa=7301 list=966c listen=9700 little=c300 live=a200
    lived=9a00 lives=9700 living=a300 loaf=5c45 loans=7601 local=a300 lois=5b35 london=a900
    longer=a300 look=bf00 looked=c400 looking=b500 looks=a100 loops=616f lord=a100 lore=5501
    los=9c50 lose=9253 loser=5a01 losers=5353 lost=a779 lot=aa00 lots=8479 love=b700 loved=a000
    low=a376 lower=9b00 luis=7b24 lungs=7d5d lust=7464 lying=9600 maar=5a01 made=c200 main=9d00
    maj=5864 major=9e01 majors=6432 make=bf00 makes=9c00 making=aa00 mama=8767 managed=9600
    management=a300 manga=7a01 mans=642e many=b900 maps=7701 mar=6347 mara=5501 mari=565f
    mark=9600 market=9f00 married=9b00 mars=7586 maru=5401 marx=639e mary=9842 mas=5586
    mast=5d8e master=9a00 material=9b00 mats=548e matter=a900 max=809e maya=6a82 maybe=b300
    mays=4bbc mean=ae00 meaning=9600 means=a500 meant=a200 medal=9c00 media=9700 medical=9800
    meet=a100 meeting=9900 meets=6f01 members=9e00 mens=3d10 mere=8301 met=a600 method=9d00
    methods=9800 mets=6483 michael=9c00 middle=9b00 might=bc00 military=9800 mind=b600 mine=9e00
    minute=9c00 minutes=a700 mir=6167 mirza=5e5c mist=795b mix=7e73 moans=6201 model=a600
    modern=9900 moment=b600 momo=3f01 money=a900 mono=549a months=9d00 moon=8f9a moor=607f
    moors=550c moran=5b01 more=cc01 morning=af00 morse=5e01 most=bc34 mother=b700 mouth=ae00
    move=a500 moved=a900 movement=9900 moving=9d00 much=c100 muir=5641 municipality=9b00
    musa=5b78 music=9800 must=b860 myself=ad00 nair=5332 name=af00 nana=5701 nas=5a4b nasa=7001
    national=a700 natural=9d00 nature=a300 near=a300 nearly=9c00 necessary=9c00 neck=a000
    need=b900 needed=aa00 needs=9d00 neither=9700 nero=5651 nes=5470 nest=7085 nets=6185
    never=c300 new=c200 news=9c00 next=b500 ngos=5a6c nice=a000 night=ba00 nodded=ab00 noir=5e01
    none=9b00 noon=777a nor=9b41 nora=5a01 norm=7001 normal=9700 norms=7a01 norse=6301
    north=9c00 nos=59d8 nose=9801 not=f000 note=9c00 nothing=ba00 noticed=9c00 now=cd5c
    number=ae00 nuns=5a01 nuts=6f86 nwa=5d2a oars=5d01 of=ff30 office=a400 often=ac00 okay=a800
    old=bb00 olympics=9900 once=b800 one=d600 ones=9600 only=c700 onto=a400 open=b100
    opened=aa00 or=d933 order=ac00 ore=5e01 organization=9800 oro=567f os=6e52 other=c600
    others=a900 our=c100 out=d900 outside=a700 over=cc00 ow=5e7a own=bbc2 owns=644d pacific=9600
    pain=a100 pair=9201 pairs=7501 pans=5901 paper=9b00 par=6f01 para=7801 parents=9e00
    paris=9a01 parma=5e01 part=b300 particular=a200 particularly=9800 parts=9513 party=a100
    pas=5b2a paso=611f passed=a300 past=ab13 pasta=5e01 patient=9b00 patients=9f00 paul=9d00
    paused=9700 paw=6401 pawn=5501 paws=6601 pays=6901 pee=5c30 peer=7501 peers=7001 pens=5c01
    people=bd00 per=a101 percent=9a00 perez=5c30 perfect=9a00 performance=9d00 perhaps=a900
    period=a000 person=a800 personal=9c00 pest=5c01 peter=9a00 pets=5a01 phone=a800 photos=7950
    physical=9c00 picked=9e00 piece=9800 pieces=8c01 pins=6302 pisa=560f pits=6421 pius=6701
    place=b700 placed=9a00 plan=9c00 play=9e00 please=a700 pleasure=9700 pocket=9700 poems=7401
    poets=6901 point=ac00 pointed=9a00 points=9700 police=9f00 policy=a100 political=a700
    poor=9e01 pops=6101 population=9a00 por=5401 pore=5f01 ports=6901 pose=6d01 position=a000
    positive=9800 possible=a700 post=9601 potential=9b00 pots=6901 pow=5318 power=ac00
    practice=a000 presence=9600 present=a400 president=9600 press=a800 pressed=9800
    pressure=9800 pretty=a400 price=9600 private=9a00 probably=a900 problem=a400 problems=9e00
    process=ac00 product=9700 production=9c00 program=9c00 project=9d00 property=9900
    provide=a100 provided=9b00 public=ab00 pull=9700 pulled=ae00 purpose=9700 pushed=9e00
    put=b900 puts=7a0e quality=9b00 quasi=689e queen=92aa queens=5c01 queer=6d01 quest=6e7f
    question=a500 questions=9d00 quick=9a00 quickly=a700 quiet=9d00 quietly=9600 quite=ab00
    quran=5ea3 raaf=5701 raf=7b64 raised=9f00 raj=6835 raja=6e01 rama=6461 rams=6c3d rana=5a17
    range=9a00 ras=5a47 rate=a000 rather=a800 rats=7061 raw=7c01 rays=6e43 reach=9600
    reached=a900 read=a600 reading=9800 ready=a700 real=a600 realized=9d00 really=b800
    reason=a400 received=9600 red=a900 reef=6a27 reefs=5d1b rees=541b ref=6b58 refer=8476
    refers=821b refuse=7b1a related=9e00 relationship=9e00 religious=9600 remained=9600
    remember=a800 remembered=9900 replied=a500 report=9f00 required=9d00 res=5c32 research=ad00
    reset=4f41 resources=9800 respect=9600 response=9c00 rest=a964 result=a100 results=a200
    return=9f00 returned=a200 review=9d00 rex=667d richard=9900 right=c400 rights=a400 risk=a100
    river=9900 road=a300 roar=7801 roast=6401 robert=a000 role=a100 rolled=9700 roof=8b82
    roofs=6101 room=be40 rooms=8b01 roots=7d85 rosa=6f01 rose=a301 rosen=5601 round=a200
    row=8456 rows=7424 rule=9700 rules=9700 running=a000 runs=7d15 rust=5998 sachs=56b4
    safe=9c00 said=dc00 same=b500 sar=5c50 sara=6c01 sas=5747 sat=b000 save=9600 saw=b901
    saying=a300 says=ad01 school=a800 science=9d00 sea=9b00 seat=9e00 second=ab00 secret=9700
    section=a500 security=9c00 see=c85a seeing=9f00 seem=9e01 seems=9b01 seen=b15a sees=8101
    self=a600 send=9600 sense=a350 sent=a100 series=9b00 service=a300 services=9f00 set=ae00
    sets=8777 seven=9600 several=a600 sex=93e4 sexes=5d01 shall=a700 she=f000 ship=9900
    shirt=9b00 shook=a900 short=a300 shot=9f00 should=be00 shoulder=a400 shoulders=9e00
    show=a500 showed=9700 shown=9d00 shows=9900 shrugged=9700 shut=9b00 side=b700 sighed=9800
    sight=9d00 sign=9800 significant=9a00 silence=9f00 silent=9800 similar=9e00 simple=9800
    simply=9b00 sims=5c01 since=b200 single=9f00 singles=9900 sins=7201 sir=a86c sis=5d32
    sister=a400 sit=9f00 sits=7a31 sitting=a300 situation=9a00 six=a0b7 size=9a00 skin=a100
    sky=9b00 sleep=a200 slightly=9700 slowly=a500 small=b200 smile=ae00 smiled=ac00 smith=9800
    social=b000 society=a200 sofa=8601 soft=9c00 some=c800 somehow=9600 someone=b000
    something=c100 sometimes=a000 somewhere=9800 songs=7a93 sons=8330 soon=ae1d sore=7501
    sorry=a800 sort=a000 sorts=7a8c soul=9600 sound=a900 sounded=9600 sounds=9700 source=9b00
    south=9e00 soviet=9900 sox=7401 space=a000 speak=a200 special=9c00 specific=a100 spent=9a00
    spirit=9600 spoke=a200 stage=9600 stairs=9700 stand=9f00 standard=9800 standing=a500
    stared=a200 staring=9800 start=a200 started=ae00 state=b300 states=ab00 stay=a800 step=9d00
    stepped=a000 steps=9900 still=c300 stomach=9700 stone=9a00 stood=b200 stop=ab00 stopped=a900
    story=a400 straight=9e00 strange=9d00 street=a400 strong=9f00 structure=9d00 students=a300
    studies=a300 study=a900 stuff=9600 subject=9d00 such=c000 suddenly=a800 sufi=5a61 sums=6201
    suns=592f support=a400 suppose=9800 supposed=9a00 sur=661d sure=b900 surf=601e surface=9a00
    surprise=9900 surprised=9b00 sweet=9800 sworn=6e01 system=b100 systems=a100 table=af00
    take=bf00 taken=a900 taking=a800 talk=ad00 talked=9600 talking=a600 tall=9600 taps=5b53
    tar=5d91 tara=5e01 tax=9466 taxa=5e01 taxi=7701 tea=9600 team=9800 tears=9f00
    technology=9900 tee=5978 teen=61be teens=6001 teeth=9800 tell=bc00 telling=9b00 tens=5f12
    tense=7901 ter=5c65 term=a001 terms=a130 test=9d38 texas=9b00 text=9800 texts=8438
    thank=a400 thanks=9c00 that=ef00 thee=8071 their=cf00 theme=7cb8 themes=7501 themselves=9f00
    theory=a000 there=d6e0 therefore=a300 these=c3da they=dd00 thick=9700 thing=b700 things=b800
    think=c400 thinking=a800 third=9f00 thirst=6549 thirty=9600 this=db89 thomas=a000 thor=5c78
    thorn=6601 those=b901 though=b800 thought=c300 thoughts=9d00 thousand=9600 three=b500
    threw=9600 throat=9d00 through=c400 thus=a7a9 tight=9600 time=ce00 times=a800 tips=7146
    tired=9600 toast=7561 today=a200 toes=7b4c together=b000 told=bc00 tomorrow=9a00 toms=4188
    tone=9800 tongue=9700 tonight=9c00 tons=6c01 too=c498 took=bd00 top=a600 tops=6e2d tor=5796
    tore=7e01 torn=8001 toro=56a8 torso=6b9f total=9d00 touch=9e00 touched=9600 tournament=a200
    tow=636f toward=ae00 towards=a400 town=a401 towns=7701 trade=9800 training=9800 trams=6047
    trans=7f70 traps=5d33 trays=5a01 treatment=9f00 tree=9a3f trees=9a01 tried=ad00 trieste=5774
    trips=6b01 trojan=5501 trojans=5601 troops=8101 trouble=9c00 true=a500 trust=996a truth=a000
    trying=ae00 tufts=543d turf=5d99 turn=a716 turned=bb00 turning=9b00 turns=8d01 twas=6107
    twenty=a100 two=c500 type=a200 types=9700 uncle=9700 under=b400 understand=a700
    understanding=9c00 university=ad00 until=b600 upon=af00 ups=6867 uri=4c78 us=c259 usa=8b3c
    usaf=5d50 usc=6589 use=b700 used=b600 using=ac00 usually=9d00 value=a600 values=9c00
    vans=5583 var=6287 various=9e00 vary=7c5f vast=8051 verse=784f very=c100 vest=685a view=a200
    vir=6446 virginia=9900 virus=7a55 visa=6851 visit=9700 voice=b700 vow=6262 vows=6184
    wait=a500 waited=9d00 waiting=a500 walk=a200 walked=af00 walking=9c00 wall=a500 walls=9700
    want=c200 wanted=ba00 wants=9700 war=a801 warm=9d00 wars=793b washington=9f00 watch=a100
    watched=a500 watching=a000 water=af00 wax=6701 way=c700 ways=9d00 wearing=9800 week=9f00
    weeks=9a00 well=c400 went=bc00 were=d800 west=9800 what=da00 whatever=a100 when=d400
    where=c300 whether=a600 which=cf00 while=bb00 whispered=9e00 white=ae00 who=ce00 whole=a900
    whom=9a00 whose=9b00 why=bf00 wide=9b00 wife=a700 will=cd00 william=a700 wind=9b00
    window=a600 wish=9e00 with=e600 within=af00 without=b700 woman=b700 women=ac00 won=853d
    wonder=9900 wondered=9c00 wong=687b word=a800 words=af00 work=b800 worked=9d00 working=a100
    works=9700 world=b500 worm=6101 worms=5b27 worn=8701 worry=9900 worse=9700 worst=8a80
    would=d800 writing=9900 written=9900 wrong=a619 yeah=a300 year=ac00 years=b500 yes=b800
    yet=b200 york=b200 you=f000 young=b000 your=d000 yourself=9f00 zealand=9a00
    """

    /// "từAnh>khoáTelexÂmTiếtSau", sắp xếp.
    private static let pairs: StaticString = """
    air>bawcs air>chems air>chi air>ddoongf air>duwowng air>haf air>hamf air>hieemr air>khar
    air>lee air>nam air>ngoax air>nooij air>pha air>quan air>vaan air>xa arm>anhr arm>ddamj
    arm>ddamr arm>taau arms>anhr arms>chir arms>haij arms>hieeuj arms>khis arms>khois arms>muif
    arms>muooij arms>sats arms>tar arms>thij arms>tieeu arms>toans arts>bichs arts>bowir
    arts>car arts>chuoonf arts>chur arts>ddi arts>lys arts>quyeenf arts>tieengs as>aau as>chaau
    as>ddoong as>dduf as>haauj as>har as>khooi as>kim as>lucj as>lyj as>nhieetj as>phieenj
    as>phu as>quaan as>raapj as>suwngf as>thais as>thanhs as>vaanj as>vaf bar>chos bar>ddang
    bar>ddi bar>nois bar>nuwax bar>phoonf bar>sex bar>sois bar>vai bar>vinh bari>bieenr
    bari>buooi bari>hoair been>bowf been>cachj been>canhj been>chais been>ddichj been>duwowis
    been>giawngf been>giuwowngf been>hoong been>kia been>leef been>manhf been>manj been>meps
    been>mes been>mowif been>mua been>nachs been>ngoaif been>nhau been>nows been>phuw been>riaf
    been>suwownf been>taauf been>tai been>tar been>theemf been>thoar been>thuee been>trais
    been>trieenf best>bangr best>car best>heets best>lowps best>nhef best>ra best>rooif
    best>trong bits>dduwowngf bits>kins bits>laij bits>taats bits>teets boom>boops boots>cao
    boots>ddieenj boots>nayf bows>cacs bows>nguwowif box>benf box>coong box>ghets box>giaf
    burn>runr burn>xinr chair>chuoots chair>ddaauf chair>ddanhs chair>ddieenj chair>loong
    chair>rawng chair>sachj chair>tocs chairs>ddown chairs>keps chairs>nhaf chest>daif
    chest>hinhf chips>chips chips>ddieenj choir>vowis cops>dduwowcj cops>nhawtj corn>con
    corps>dduwowcj corps>nhawtj cost>kets cost>nan dar>thowif darts>mongr darts>ngocj
    darts>vangf days>nguwowif deer>beef deer>dangf deer>duooi deer>hieeur deer>nguwowi
    deer>thuwowng dense>ngayf dense>nooix dense>nowi der>cuwowif der>gai der>hoongf der>nguwaj
    down>vij downs>dacs ems>nhemj ems>quaan est>o gary>bawngf gary>daay gary>ddanf gary>ddownf
    gary>khucs gary>tai gas>bacj gas>lawps gas>nghiax guts>caaps hair>aaps hair>aau hair>caaur
    hair>cangr hair>ddaor hair>ddawng hair>ddieens hair>dij hair>duwowng hair>huwng hair>khaaur
    hair>lawng hair>luwuj hair>ly hair>max hair>mieen hair>ngoaij hair>ninh hair>phaos
    hair>phongf hair>quaan hair>quan hair>quyf hair>saam hair>sanr hair>taor hair>tawcj
    hair>thuyj hair>trieeuf hair>vaan hair>vuwowng hair>yeens has>caor has>chawngr has>chiuj
    has>cos has>dams has>deex has>has has>hoocs has>laij has>lex has>mieengj has>moomf has>neen
    has>nowx has>phair has>rawngf has>roongj has>sex has>sowj hasan>gif hasan>thuj hasan>vowis
    hays>puf here>har hero>lanhs hers>cawpj hers>cuwar hers>hes hers>looj hers>mawts
    hers>mieengj hers>mooi hers>mowr hers>nowr hers>nuj hers>nuwar hers>ra hers>rawng hips>laij
    hips>mawts his>his his>hoaj his>hoays his>hownr his>huwngr his>huwowcs his>khucs his>kichj
    his>mawts his>truwowngf his>vieenj his>vowis honor>chieens honor>ddoonj honor>haof
    honor>heenr honor>howpj honor>loanj honor>soos host>been host>ddanhs host>hay host>lius
    host>racs host>treen host>vang how>hair how>haix how>hongr how>how how>hows how>howts
    how>luwar how>nongs if>achj if>ra if>sua ira>chayr ira>ddunf ira>ra ira>vaof is>dduwcs
    is>giaos is>i is>meenhf is>ow is>owis keen>keen keeps>cho last>banhs last>cawts last>chanh
    last>daif last>ddas last>gachj last>gawpj last>goox last>guwngf last>khoai last>mongr
    last>neenf last>nhes last>nuwax last>owts last>rooif last>sanf last>sau last>thitj
    last>thooi last>vans laura>bof laura>cas laura>cua laura>ddieenj laura>dee laura>gaf
    laura>mawms laura>nuwowngs laura>thais les>mawts lest>phongf lest>tooi lest>vaf lets>phongf
    lets>tooi lets>vaf list>bia list>daauf list>khis list>maus list>mooix list>nhieen list>nhits
    list>nuwowcs list>ruwowuj list>suwax list>trowr list>xawng loaf>loaf loaf>mawts loaf>xoaf
    los>cais los>dangj los>ddaauf los>leen los>mawtj los>mocj los>moif los>ra los>rangj
    lose>bungf lose>leen lose>ra lose>sangs lost>bawngf lost>been lost>cho lost>chuwx lost>cuar
    lost>daay lost>daj lost>ddas lost>dduwowngf lost>duwowis lost>gachj lost>giaays lost>giayf
    lost>las lost>longf lost>mauf lost>nuwx lost>oor lost>phuj lost>sanf lost>tay lost>vans
    low>bacj low>ddangx low>ddaps low>ddeenhx low>khow low>laf low>langr low>langx low>laos
    low>low low>lows low>luwngr low>luwngx low>mow low>ngow low>rawngf low>thow low>xanh
    luis>huis lungs>bungs lungs>tungs mama>banhs mama>bats mama>cao mama>cau mama>coox mama>cowm
    mama>cungs mama>ddoongf mama>leex mama>ngux mama>nhieetj mama>quar mama>ruwowuj mama>son
    mama>thau mama>traauf mama>vangf mama>xe mama>xooi mans>meof mans>owr mar>cha mar>cux
    mar>ddamj mar>gaf mar>mej mar>nguoonf mar>oong mar>soos mar>toor mar>vua mary>buij
    mary>loong mary>may mary>muns mist>ddawcj mist>tinh mist>toos mist>treen mist>uwowts
    moors>caauf most>dduwowcj most>luas muir>longf muir>teen must>canhs must>ddas must>laays
    must>loong must>ngons must>tay nair>chuoois nor>bawns nor>cuwngs nor>lieen nor>manhj
    nor>moomf nor>thaanf now>buwowms now>canh now>ddor now>ron now>sau now>trang now>vits of>os
    or>trangj os>bieenr os>leen os>o os>vang owns>lanhj owns>quas pans>taanr par>vi pas>khoang
    pas>vi pee>ddan pee>ddee perez>ddan perez>ddee photos>phats photos>pho pits>toong pow>mu
    raf>nhowf raf>phas raf>soats rams>nawngs rana>rats rays>tai reef>raf reef>reef res>leen
    rest>buoots rest>cawm rest>congs rest>ddaamj rest>haij rest>lanhj rest>lawms rest>muwowts
    rest>nhuw rest>quas rest>run rest>ruwngf rest>thif room>rar room>sayr row>benf row>dduwowng
    row>le row>mawm row>moocs row>rawngf row>thuwa see>benf see>ddaps see>poon see>rawngf see>ri
    see>san seen>bieenr seen>dduwowcj seen>hoa seen>truyeenf sense>quas sense>saamr sense>suas
    sins>chair sins>chengs sins>thaauf sir>ler sir>nhucj sir>var sits>sao sons>ra sons>tieeur
    suns>rawng surf>sif surf>suf surf>suj tax>cho tax>giaays tax>lots terms>laij terms>tems
    test>ddits test>moong texts>ddits texts>moong thirst>chawtj thirst>khocs this>chur
    this>ddieemr this>duj this>mangj this>nghichj this>nghieemj this>sinh this>vor this>vox
    tips>nguwowif toast>car toast>heets toast>leen toast>moof toast>ra toast>yeeus toes>khawps
    toes>leen toes>luwar toes>ra too>buns too>buyts too>caamr too>chaos too>chowr too>ddaam
    too>ddaamj too>doanx too>hapj too>hieens too>hoaif too>khaats too>kieemf too>lawcj too>maauf
    too>matj too>mauf too>mif too>moocj too>ngocj too>phowr too>poo too>ree too>son too>taanf
    too>tair too>thaams too>thawms too>thuees too>trieetj too>uyeen too>vex tops>mowx trams>dden
    trams>rawng trams>trawngs trams>vaof traps>ddi traps>laays tree>cocs tree>tuyeens
    trust>baauf trust>bats trust>bor trust>cown trust>ganhs trust>giaanj trust>heets trust>howi
    trust>leen trust>linh trust>nooix trust>nuwowcs trust>ra trust>sachj trust>vaof
    trust>xuoongs tufts>tats tufts>tuts turn>munr us>oaf us>ows usa>tanf usa>vangf vary>bawcs
    vary>cas vary>gaf vary>lieen vary>lowns vary>nayf vary>neens vary>nhor vary>roongf
    vary>suwngf vary>treen vary>xuwowng vast>ddepj verse>ddaauf verse>ddoois verse>duwowis
    verse>ngawn verse>phair verse>sau verse>thuws verse>trais verse>treen verse>truwowcs
    vir>nhuees vir>nuwowngs vir>thuoocs virus>laays virus>luwowngj virus>truwowngf virus>vaof
    visa>baf visa>kinh visa>phaatj visa>thaanf wars>gan wars>hai wars>leej wars>luyj
    wars>nuwowcs wars>ra won>henf won>uwowts worms>hoir worms>thuwr
    """

    /// (en, vn) của từ `key[0..<n]` (chữ thường a–z), nil nếu không có. Không cấp phát.
    static func scores(_ key: UnsafeBufferPointer<UInt8>, count n: Int) -> (en: UInt8, vn: UInt8)? {
        guard n >= 1, n <= maxWordLength else { return nil }
        return words.withUTF8Buffer { buf in
            guard let s = find(buf, key, n, sep: 0x3D) else { return nil }
            return (hex(buf, s + n + 1), hex(buf, s + n + 3))
        }
    }

    /// Cặp `key[0..<n]` (đã gồm dấu ">") có trong bảng PAIRS. Không cấp phát.
    static func hasPair(_ key: UnsafeBufferPointer<UInt8>, count n: Int) -> Bool {
        guard n >= 3, n <= maxPairLength else { return false }
        return pairs.withUTF8Buffer { buf in find(buf, key, n, sep: 0) != nil }
    }

    @inline(__always) private static func nib(_ b: UInt8) -> UInt8 { b <= 0x39 ? b &- 0x30 : b &- 0x57 }
    @inline(__always) private static func hex(_ buf: UnsafeBufferPointer<UInt8>, _ i: Int) -> UInt8 {
        nib(buf[i]) << 4 | nib(buf[i + 1])
    }

    /// Tìm nhị phân token có phần đầu (tới `sep`, hoặc cả token khi sep = 0) đúng bằng key[0..<n].
    /// Trả về vị trí đầu token.
    private static func find(_ buf: UnsafeBufferPointer<UInt8>, _ key: UnsafeBufferPointer<UInt8>,
                             _ n: Int, sep: UInt8) -> Int? {
        @inline(__always) func isSpace(_ b: UInt8) -> Bool { b == 0x20 || b == 0x0A }
        var lo = 0, hi = buf.count
        while lo < hi {
            var s = (lo + hi) / 2
            while s > lo, !isSpace(buf[s - 1]) { s -= 1 }
            if isSpace(buf[s]) {
                var t = s
                while t < hi, isSpace(buf[t]) { t += 1 }
                if t >= hi { hi = s; continue }
                s = t
            }
            var e = s
            while e < buf.count, !isSpace(buf[e]) { e += 1 }
            var k = e
            if sep != 0 { k = s; while k < e, buf[k] != sep { k += 1 } }
            var cmp = 0, i = 0
            while i < n, s + i < k {
                let a = buf[s + i], b = key[i]
                if a != b { cmp = a < b ? -1 : 1; break }
                i += 1
            }
            if cmp == 0 {
                let tl = k - s
                if tl == n { return s }
                cmp = tl < n ? -1 : 1
            }
            if cmp < 0 { lo = e } else { hi = s }
        }
        return nil
    }
}
