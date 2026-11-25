"""Make html/js/builder-peds.js (the Director world builder's NPC list) from RDR2's peds.

RedM (spur_core, 24 Nov 2026). whip_core's list is GTA V's 881 peds; none of them exist in RDR2, so picking one placed
nothing. This makes the same file (PED_CLUSTERS, PED_CATEGORIES, PEDS) from femga's RDR2 ped list:

    https://github.com/femga/rdr3_discoveries/blob/master/peds/peds_list.lua   (data only: hash, model, outfits)

Run:  python -I dev/builder_peds_rdr.py <path to peds_list.lua>   (writes html/js/builder-peds.js)
      add --residue to print the name pieces the word list could not split (to grow WORDS below).

Names are made from the model names: a place code ("val" Valentine, "nbx" Saint Denis), then words found in WORDS,
then sex and age from the prefix ("a_m_y_" a young man). A piece WORDS can't split is shown as it is, capitalised.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'html', 'js', 'builder-peds.js')

# Not people or animals: saddles and a horse prop that the list also carries.
SKIP = re.compile(r'(_saddle_\d+$|^p_c_horse_01$)')

PLACES = {
    'val': 'Valentine', 'rhd': 'Rhodes', 'sd': 'Saint Denis', 'nbx': 'Saint Denis', 'lowersd': 'Lower Saint Denis',
    'middlesd': 'Middle Saint Denis', 'blw': 'Blackwater', 'str': 'Strawberry', 'asb': 'Annesburg', 'vht': 'Van Horn',
    'arm': 'Armadillo', 'tum': 'Tumbleweed', 'btc': 'Butcher Creek', 'lag': 'Lagras', 'emr': 'Emerald Ranch',
    'rkr': 'Roanoke Ridge', 'htl': 'Heartlands', 'gri': 'Grizzlies', 'scl': 'Scarlett Meadows', 'byn': 'Bayou Nwa',
    'biv': 'Big Valley', 'gua': 'Guarma', 'wap': 'Wapiti', 'wal': 'Wallace', 'nea': 'New Austin',
    'skp': 'Sisika', 'tlj': "Thieves' Landing", 'wtc': 'West Elizabeth', 'bwm': 'Blackwater', 'rig': 'Riggs',
    'lns': 'Lemoyne', 'isl': 'Island', 'cmr': 'Colter', 'uni': '', 'gen': '', 'ambient': '', 'rho': 'Rhodes',
}

WORDS = """
abe aberdeen abigail about acrobat act adam adler agent agnes al albert alden alfredo all allbright alley allen
alligator alone alter amateur ambush america american amos anders andalusian
angel angry angus animal annesburg announcer ansel antony appaloosa appraiser arabian archer archibald archie arctic
ardennes arm armadillo armored army arrest art arthur artist ash ashton assassin assistant atherton attack auction
auntie aunt baby back backup badger bait baker ball balloon band bandit bandito banditos bank banker bar barber barn
bartender bass bassist bat bay bayou beach bear bearded bears beau beaver beecher beechers beggar belgian
belle ben benedict bertram big bighorn bill billy bird birds bison black blackbelle blackwater blanket blood bloody
blue bluejay boar boat body bodies bones bonnie boss bounty boy boys braithwaite braithwaites
brawler breach breton brick bride brindle bronte brood brother brothers brown buck buckskin buell buffalo bull bully
bum burning bush bushwhacker butcher butchers butler buttermilk by cabaret cage caged cajun calderon calf calloway
camp candy cannibal cap captain captive card cardinal carolina carpet cart catch cat cattle cave cedar
center chain champagne charles charlotte chase cheaters chelonian chestnut chicken chief child children chinatown
chinese chipmunk choir cholera church circus city civil clan class claude clay clerk club coach 
cob cobbler cold collector colm colonel commando companion condor confed confederate confeds conductor consequence
contract cool cop copperhead cormorant corn cornwall corpse corpses cougar cousin cow cowboy cowpoke coyote crab crack
crackpot crane crashed crawfish creek creeper creole cremello criminal criminals criollo crow crowd crows custom
dad dancer dappled dapple dark daughter david dead deadman dealer dealers death debtor deer deputies deputy
desert dick digger dino disabled dispatch distiller doc doctor dog dogs domestic dominoes donkey door doorman dorothea
downes driver drivers drowned drown drowning drummer drunk dry duck duel duelist duellist dun duster dutch 
eagle east edith edmund egret elephant elk elysian emerald engineer escape escort evelyn exconfed exconfeds
executed executioner exotic exotics express factory fairground falls family fancy farm farmer farmhand fat father
favor feed feud few fiance fiddle field fight fighter filet fillet finale fire firehat fish fisher fisherman five fleabitten
flaxen fog foreman foremen fort fortune fox frank freight friend frog fry fussar gal gala gambler gamble
game gang gap garden gator geddes general gentleman george geese girl goat gold golden goon goons goose gopher grave
 gray grays green grey grizzlies grizzly grullo guard guards guarma gull gun gunslinger gunsmith gypsy hag
hagen hair halfbred hall hammer hand harbor harbormaster hare harlow harriet hawk head heartlands helgerson henchman
henry herbalist here hermit heron high hill hillbilly hilltop hitch hobo hog holdup home homestead
honey horse horses hosea hotel hound housewife hungarian hunt hunter hunters hunting husband ice ill
inbred indian industry infected informant informants inmate interrogator iron isabella island jack jail jailer james
jameson javelina jay jim jimmy joe john johnny josiah journalist juggernaut juggernauts jumper keeper kentucky kid
kidnapped kids king kirk kitty kladruber kong labor laborer laborers lady lagras lake landing langston laramie
lasso law lawman lawmen lawyer leader leaf legendary lemoyne lenny leopard leviticus liar light line lion 
liver livery lizard loan loansharking lobby lone lord lost lover lower lumber lumberjack lunatic macfarlane magic
mahogany maid male males man manager mangy manor manzanita map marie market marshall marshalls mary mason master
mauled mauling mayor mcgee mean medic men mercer merchant micah middle mill miller miner miners mine minister mob
mob mole money moonshine moonshiner moonshiners moose morgan mother mountain mourner mp mr mrs mud mudtown
murder murfee murfree music musician muskrat mustang nate nathan native natives new news newspaper night nokota
norfolk nude nurse oddfellow oddfellows odriscoll odriscolls official officer old oldman on one operator opossum orchard
oriole otter out outlaw outlaws overo owl owlhoot owner ox paint panther parakeet parrot participant passenger
passengers pearson peeping pelican penelope perlino pheasant photographer pianist pig pigeon pike pikes pimp
pinkerton pinto pit player players pocket poison poisoned poker police poor porch possum post
prairie preacher priest prince princess prison prisoner prisoners pronghorn prospector prostitute pump quail quarter
quartermaster quartet rabbit rabicano raccoon race racer railroad railway rail ram ranch rancher ranchers ranger
rat rattlesnake raven reader rebel recipient recipients red redback resident retired returned
reverse revenue rhodes rich ride rider rifle rifleman ring rival river riverboat road roadster roan robber robbery
roberts rock rocky rodeo rooster rose rough runaway rural sadie saint saloon salvation sam sample
sandy saw scarlett scarecrow scavenger school sea seal search sec seller serial servant servers service sharp
sharpshooter shack shady sheep sheriff sherriff shire shoe shop shopkeeper shot sick silver singer sister skeleton
skiff skinner skinny skunk sleeping slums small smoky snake snow society soldier son sooty sorrel spanish spectre
splashed spoonbill sport spot squirrel stable stablehand stage stagecoach stake stakeout standardbred star starving
station statue steamboat steel stillwater stoat stone store strange stranger strawberry street string
strong suffolk survivalist suspended swamp swan sweet table tailor tall tanner target tattoo taxi teacher
teen teens tenant tennessee the theater thief thieves thomas thoroughbred thug ticket tiger tobiano
toad tobacco tom tommy torture tough tourist town townfolk townsfolk track tracker trader train trainee trap trapper
travel traveler travelers traveller travellers treasure trees trelawny trial tumbleweed turkey turkoman turtle twin
uncle undertaker uniform union upper uprisers valentine van vendor veteran victim victims vip vips
volunteer vulture wagon waiter walker wall wanted war warm warrior warriors wash watch water wealthy wedding
welcome well west white whore wide widow wife wild wildman winter witness wolf woman women wood woodpecker woods
worker workers wormwood wounded yard young zombie
accomplice adair african agnes dowd albert cake esquire allison ambarino amber approach arrested poacher poachers
fear bag holders barbs barricade bath bathing ladies beaten up breather bribe brontes butler sec form bubba bullet
buyer buyers mc camp def cancan canoe monroe rustler central rr checkpoint contact convoy cook crackpot inventor
robot crater sacrifice creepy guy cult members capitali default delivery dello bo party disguised dlc dock dockworker
dockworkers fight drop off dueler boaster winner dying endless summer executions famous feats of strength female
females ref fleeing foot forgiven freeroam french frenchman friendly outdoorsman frozen to fundraiser gila monster
panner canada grizzled jon hire handshaker shaker hostage marshal rescue hwy improved kidnap infiltration injured
intercept intro break known laperle masked unmasked rustling lead loft mange meditating monk medium mercs mistaken
bounties mixed race makers big package relay multi suicide mysterious naked swimmer obese pinhead opera looter parlor
passerby pelt photography pickpocket piss pot camp strangers well shaman formal pooping praying predator protect
public hanging infestation receptionist recover recovery footed booby regular repo resupply revenge agents lightning
cronies charge seven rogue roseate saboteur saddle patrons samaritan savage aftermath warning security shaky shotgunner
show skipping stones slave catcher slum slumped smith smuggler bite songbird soothsayer sparrow special stalking steal
stranded sun worshipper freak weirdo sonny sword targets tatanka taunting taxidermist handler tiny burial confrontation
crier intro trapped saleswoman travelling snapping groupie vampire vigilante vigilantes voice threat vet vets washed
ashore couple welsh western xl australian sheperd bluetick coonhound catahoula cur chesbay retriever collie husky lab
poodle rufus bluegil chain pickerel channel catfish sturgeon largemouth longnose gar muskie northern perch rainbow
trout redfin salmon sockeye smallmouth blacktail rattle ferdelance boa ft shark hammerhead frame overo tovero blond
chocolate spotted palomino mealy marble sabino piebald sable silvertail skewbald speckled tricolor striped warped
blagdon fox trotter missouri waxwing whooping canada desert iguana snapping
bartholomew bill williamson brenda crawley brynn tildon calhoun carmela cassidy catherine smith cleet clive cooper cortez
covington cripps dale maroney danny davenport davey callender davies desmond didsbury dorkins doroethea wicklow higgins
malcolm macintosh duncan edgar ross downes lowry featherston chambers finch francis gareth gavin gerald german gilbert
knightly gloria grace guido martelli gus hamish hans hector fellowes hennigans henri lemiux hercule heston hixon hobart
horley hosea matthews ian jamie janson javier escuella jeb jeremiah jessica jock weathers jones jorge jules karen karens
kieran lambert lancing lansing lee leigh lem leon leo strauss levi simon lillian powell lilly millet lonnie lonnies luca
napoli mabel macfarlanes macleans macmillan maggie magnifico mama watson marjorie beth linton meredith merediths mickey
millesani milton andrews moira molly oshea montez ned nial nicholas timmins nils norris forsythe obediah hinton paytah
pleasance isabeau professor bell reverend fortheringham rev swanson ricard riley rileys robin sean senator seth shaw
freeman owens sinclair susan grimshaw tavish teddy terrance theodore levin donahue dickens trelawney trelawny warner
whelan winton holmes wrobel wayne devon londonderry fellows nemesis scott timothy marston micah down grizzled
aurora basin barrow lagoon caliga cholla springs colter cumberland diablo ridge dover hanover elysian gaptooth plains
hollow hanging little montana moonstone painted sky quakers cove radleys pasture rio bravo roanoke stead tall two rocks
utopia rathskeller plaguetown mtn infinite brk wgn tvl fence lom fos prsn oth lbt hctel asn trk asntrk
iti valley story high society lantern mugging dispute cliff missing crew point debt horde run silent food horn pool
hide noble wise return rowdy finger bottle tree meadows halloween december california favours baptiste baptising
madman cig sailor bouncer torturing rally setup thurwell fordham miss kid dr mr mrs ms rev chu rob de gam caj rac
great bandits pinlaw and for my snowflake loon doctors micahs rains fall tilly graves standoff philips
fathers stabbing drunks secret killer bessie forman samson wedding manor isabella grizzlies coronado bluewater marsh stillwater pikes fort mercer
punch warmblood denis society flies corpse
"""

CAT = {
    'men': 'men', 'women': 'women', 'services': 'services', 'gangs': 'gangs', 'unique': 'unique',
}

CLUSTERS = [
    ('people', 'People', 'person'),
    ('characters', 'Story & Missions', 'person'),
    ('online', 'Online', 'person'),
    ('animals', 'Animals', 'paw'),
]
CATEGORIES = [
    ('men', 'Men', 'people', 'person'),
    ('women', 'Women', 'people', 'person'),
    ('services', 'Services', 'people', 'person'),
    ('gangs', 'Gangs', 'people', 'person'),
    ('unique', 'Unique', 'people', 'person'),
    ('story', 'Story', 'characters', 'person'),
    ('encounters', 'Encounters & Missions', 'characters', 'person'),
    ('online', 'Online', 'online', 'person'),
    ('horses', 'Horses', 'animals', 'paw'),
    ('animals', 'Animals', 'animals', 'paw'),
]

VOCAB = set(WORDS.split())
RESIDUE = {}


def split_words(token):
    """Split a run of letters into WORDS (fewest pieces, unknown letters cost most); unknown runs stay whole."""
    n = len(token)
    cost = [0] + [None] * n
    back = [None] * (n + 1)   # (start, known)
    for i in range(n):
        if cost[i] is None:
            continue
        for j in range(i + 1, n + 1):
            w = token[i:j]
            known = w in VOCAB or w in PLACES
            # A word; a place code, a little dearer (so 'armored' is a word, 'armtownfolk' Armadillo's); or a run of
            # letters no word explains, dear, and dearer the longer it is (so 'czphomesteadson' is CZP Homestead Son).
            c = cost[i] + (1 if w in VOCAB else 1.2 if known else 5 + 0.6 * (j - i))
            if cost[j] is None or c < cost[j]:
                cost[j] = c
                back[j] = (i, known)
    pieces = []
    j = n
    while j > 0:
        i, known = back[j]
        pieces.append((token[i:j], known))
        j = i
    pieces.reverse()
    out = []
    for w, known in pieces:
        if not known and out and out[-1][1] is False:
            out[-1] = (out[-1][0] + w, False)   # unknown letters in a row stay one piece
        else:
            out.append((w, known))
    for w, known in out:
        if not known:
            RESIDUE[w] = RESIDUE.get(w, 0) + 1
    return [w for w, _ in out]


def words_of(part):
    """'valtownfolk' -> ['Valentine', 'Townsfolk']; 'tennesseewalker' -> ['Tennessee', 'Walker']."""
    out = []
    for piece in re.findall(r'[a-z]+|\d+', part.replace('_', ' ')):
        if piece.isdigit():
            if out:
                out.append(str(int(piece)))   # 'dutch1' -> Dutch 1, 'winter02' -> Winter 2
            continue
        for w in split_words(piece):
            if w in PLACES and w not in VOCAB:
                if PLACES[w]:
                    out.append(PLACES[w])
            elif w == 'arm' and len(piece) > 3:
                out.append('Armadillo')   # 'armtownfolk'; 'arm' alone stays a word
            else:
                out.append(w)
    nice = []
    for w in out:
        w = {'townfolk': 'townsfolk', 'sherriff': 'sheriff', 'odriscoll': "O'Driscoll", 'odriscolls': "O'Driscolls",
             'mp': '', 'chu': '', 'de': '', 'rob': 'robbery', 'dr': 'Dr', 'mr': 'Mr', 'mrs': 'Mrs', 'ms': 'Ms',
             'rev': 'Rev', 'bht': '', 'mc': 'MC', 'exconfed': 'Ex-Confederate', 'exconfeds': 'Ex-Confederates', 'forman': 'foreman', 'pinlaw': 'Pinkerton lawman', 'bluegil': 'bluegill', 'sheperd': 'shepherd'}.get(w, w)
        if not w:
            continue
        small = w in ('the', 'of', 'to', 'on', 'by', 'for', 'and', 'up', 'off', 'out') and nice
        code = w.islower() and w not in VOCAB and len(w) <= 3 and not re.search(r'[aeiou]', w)
        nice.append(w.upper() if code else w if w[0].isupper() or small else w.capitalize())
    return nice


SEX = {'m': 'Male', 'f': 'Female'}
AGE = {'y': 'Young', 'o': 'Old', 'm': ''}
GROUP = {'males': 'Men', 'females': 'Women', 'teens': 'Teens', 'dogs': 'Dogs'}


def number_of(model):
    m = re.search(r'_(\d+)$', model)
    return int(m.group(1)) if m else None


def name_and_category(model):
    m = model
    online = m.startswith('mp_') and m not in ('mp_male', 'mp_female')
    if m in ('mp_male', 'mp_female'):
        return ('Online ' + ('Male' if m == 'mp_male' else 'Female') + ' (freemode)', 'online')
    if m in ('player_zero', 'player_three'):
        return ('Arthur Morgan' if m == 'player_zero' else 'John Marston', 'story')
    if m in ('male_skeleton', 'female_skeleton'):
        return (('Male' if m.startswith('male') else 'Female') + ' Skeleton', 'unique')
    core = m[3:] if online else m
    size = ''
    sm = re.match(r'^(.*_\d+)_(lg|ml|ms|sm|xl)$', core)   # a fish's size: a_c_fishsalmonsockeye_01_lg
    if sm:
        core, size = sm.group(1), {'lg': ' (large)', 'ml': ' (medium-large)', 'ms': ' (medium)', 'sm': ' (small)',
                                     'xl': ' (XL)'}[sm.group(2)]
    body = re.sub(r'_\d+$', '', core)

    # Animals: a_c_<kind>, horses a_c_horse_<breed>_<coat>.
    am = re.match(r'^a_c_(.+)$', body)
    if am:
        rest = am.group(1)
        if rest.startswith('horse_'):
            parts = [p for p in rest.split('_')[1:] if p and p != 'pc']   # '_pc': a coat the PC edition added
            if not parts:
                return ('Horse', 'horses')
            breed = ' '.join(words_of(parts[0]))
            coat = ' '.join(words_of('_'.join(parts[1:]))) if len(parts) > 1 else ''
            return ((breed + (', ' + coat if coat else '')) or 'Horse', 'horses')
        return ((' '.join(words_of(rest)) or rest) + size, 'animals')

    # People with a sex and age: a_ (ambient), s_ (services), g_ (gangs), u_ (unique).
    pm = re.match(r'^([asgu])_([mf])_([myo])_(.+)$', body)
    if pm:
        kind, sex, age, rest = pm.groups()
        cat = {'a': 'men' if sex == 'm' else 'women', 's': 'services', 'g': 'gangs', 'u': 'unique'}[kind]
        if online:
            cat = 'online'
        ws = words_of(rest)
        bits = [AGE[age]] + ws + [SEX[sex]]
        return (' '.join(b for b in bits if b), cat)

    # Story characters: cs_<name>.
    if body.startswith('cs_'):
        return (' '.join(words_of(body[3:])) or body, 'online' if online else 'story')

    # Encounters and missions: re_<what>_<males|females>, rcsp_, msp_, mes_ ... A sex and age code may sit inside
    # ('mp_de_u_f_m_bigvalley_01'): it is said at the end, as for the people above.
    tail = []
    em = re.search(r'(?:^|_)[asgu]_([mf])_([myo])(?:_|$)', body)
    if em:
        tail = [AGE[em.group(2)], SEX[em.group(1)]]
        body = (body[:em.start()] + '_' + body[em.end():]).strip('_')
    parts = body.split('_')
    group = None
    if parts and parts[-1] in GROUP:
        group = GROUP[parts[-1]]
        parts = parts[:-1]
    tag = parts[0] if parts else ''
    if tag in ('re', 'rces', 'rcsp', 'msp', 'mes', 'casp', 'amsp', 'gc', 'ge', 'cr', 'mbh', 'shack', 'loansharking',
               'am', 'asn', 'asntrk', 'fm', 'lbt', 'bht'):
        parts = parts[1:]
    ws = words_of('_'.join(parts)) + [t for t in tail if t]
    name = ' '.join(ws) or body
    if group:
        name += ' (' + group + ')'
    return (name, 'online' if online else 'encounters')


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        sys.exit(1)
    src = open(args[0], encoding='utf-8').read()
    models = []
    seen = set()
    for raw in re.findall(r'\{0x[0-9A-Fa-f]+,"([^"]+)"', src):
        model = raw.lower()
        if model in seen or SKIP.search(model):
            continue
        seen.add(model)
        models.append(model)

    rows = []
    for model in models:
        name, cat = name_and_category(model)
        rows.append([model, cat, name])

    # "#n": the n-th of a name, counted in the list's order of the model numbers, as the GTA list counts them.
    order = {c[0]: i for i, c in enumerate(CATEGORIES)}
    rows.sort(key=lambda r: (order[r[1]], r[2].lower(), number_of(r[0]) or 0, r[0]))
    counts = {}
    for r in rows:
        counts[(r[1], r[2])] = counts.get((r[1], r[2]), 0) + 1
    nth = {}
    for r in rows:
        key = (r[1], r[2])
        if counts[key] > 1 or r[1] in ('men', 'women', 'services', 'gangs'):
            nth[key] = nth.get(key, 0) + 1
            r[2] = r[2] + ' #' + str(nth[key])

    # The same name in two categories (mp_a_m_m_valtownfolk_01 is an online copy, u_m_m_valtownfolk_01 a unique one):
    # the first category's keeps it, the others' say their category, for search.
    label = {k: lab for k, lab, *_ in CATEGORIES}
    first = {}
    for r in rows:
        first.setdefault(r[2], r[1])
    for r in rows:
        if first[r[2]] != r[1]:
            r[2] += ' (' + label[r[1]] + ')'

    if '--residue' in sys.argv:
        for w, c in sorted(RESIDUE.items(), key=lambda x: -x[1]):
            print(c, w)
        print(len(RESIDUE), 'pieces not split')
        return

    import json
    per = {}
    for r in rows:
        per[r[1]] = per.get(r[1], 0) + 1
    lines = []
    lines.append('// ========================================')
    lines.append("// THE WORLD BUILDER'S NPCs (the Director's World tab): RDR2's peds")
    lines.append('//')
    lines.append('// RedM (spur_core, 24 Nov 2026): whip_core listed GTA V\'s 881 peds here, none of which RDR2 has, so picking one')
    lines.append('// placed nothing. These are RDR2\'s, %d of them, from femga\'s rdr3_discoveries peds/peds_list.lua (saddles left' % len(rows))
    lines.append('// out). The names are made from the model names (dev/builder_peds_rdr.py: a place code, its words, sex and age),')
    lines.append('// so a few read oddly; search finds the model name too. There are no pictures of RDR2 peds yet: a tile shows')
    lines.append('// its glyph. A ped is still placed with "By name".')
    lines.append('//')
    lines.append('// A ped a game build does not have is refused when picked (client/property_furnish.lua asks the game).')
    lines.append('// Do not edit by hand: regenerate it with python -I dev/builder_peds_rdr.py <peds_list.lua>.')
    lines.append('// ========================================')
    lines.append('')
    lines.append('export const PED_CLUSTERS = [')
    for k, label, g in CLUSTERS:
        lines.append("    { key: %s, label: %s, glyph: %s }," % (json.dumps(k).replace('"', "'"), json.dumps(label).replace('"', "'"), json.dumps(g).replace('"', "'")))
    lines.append('];')
    lines.append('')
    lines.append('export const PED_CATEGORIES = [')
    for k, label, cl, g in CATEGORIES:
        lines.append("    { key: '%s', label: '%s', cluster: '%s', glyph: '%s' }," % (k, label.replace("'", "\\'"), cl, g))
    lines.append('];')
    lines.append('')
    lines.append('/** [model, category, name] */')
    lines.append('const ROWS = [')
    for r in rows:
        lines.append('    ' + json.dumps(r, ensure_ascii=False, separators=(',', ':')) + ',')
    lines.append('];')
    lines.append('')
    lines.append('export const PEDS = ROWS.map((r) => ({ model: r[0], category: r[1], name: r[2] }));')
    lines.append('')
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines))
    print('wrote', len(rows), 'peds:', ', '.join('%s %d' % (k, per.get(k, 0)) for k, *_ in CATEGORIES))


if __name__ == '__main__':
    main()
