"""Make server/prop_catalog_seed.lua (the furnisher's prop catalog) from RDR2's objects.

RedM (spur_core, 24 Nov 2026). whip_core's catalog was the original game's props; none of them exist in RDR2, so the world builder's
Props tab was empty. This makes the same file (PropCatalogSeed, one { model, category, name } a line) from femga's
list of RDR2 object names:

    https://github.com/femga/rdr3_discoveries/blob/master/objects/object_list.lua   (data only: hash, name, archive)

Run:  python -I dev/prop_catalog_rdr.py <path to object_list.lua>   (writes server/prop_catalog_seed.lua)
      add --stats to print how many land in each category with a few of each, --residue for the name pieces the word
      list below could not split (to grow WORDS).

What goes in: props from the archives a builder would furnish with (generic, interior, structure, urban, areas,
vegetation, vehicle props, weapons' world models and the level designers' sets), not peds, vehicles, wheels, effects,
map pieces (lod, slod, collision, fragments) or the 500 single playing cards. Each archive either gives its category
(p_food.rpf is Food & drink) or, for a mixed one (p_household.rpf), the words in the name do (KEYWORDS), with the
archive's category when none match. A wrong guess is one /prop add <category> away.

Names are made from the model names: prefixes off (p_, s_, mp005_), words found in WORDS split apart, numbers kept
("p_barberchair01x" is "Barber chair 01"). The furnisher's search reads the model too, so a name only helps.

Left out too: the props in dev/prop_catalog_rdr_nospawn.txt, which /propcheck found the game will not spawn (nearly all
doors and gates).
"""
import collections
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'server', 'prop_catalog_seed.lua')
NOSPAWN = os.path.join(HERE, 'prop_catalog_rdr_nospawn.txt')


def read_nospawn():
    """The models /propcheck found the game will not spawn (one a line, # comments)."""
    if not os.path.exists(NOSPAWN):
        return set()
    with open(NOSPAWN, encoding='utf-8') as f:
        return {l.strip().lower() for l in f if l.strip() and not l.lstrip().startswith('#')}

LINE = re.compile(r'^\s*\[(-?\d+)\]\s*=\s*"([^"]+)"\s*,\s*--\s*hex_hash:\s*(0x[0-9A-Fa-f]+)\s*--\s*(.*?)\s*\|\s*(\S+)\s*$')

# ---------------------------------------------------------------------------------------------------------------
# Archives. FIXED: everything in it is that category. MIXED: KEYWORDS decide, else that category.
# ---------------------------------------------------------------------------------------------------------------

FIXED = {
    # generic
    'p_food.rpf': 'food', 'p_drink.rpf': 'food', 'mp004_p_kitchen.rpf': 'kitchen', 'p_kitchen.rpf': 'kitchen',
    'p_curtain.rpf': 'decor', 'p_door.rpf': 'doors', 'p_door02.rpf': 'doors', 'p_fence.rpf': 'barriers',
    'p_sign.rpf': 'signs', 'p_mpcover.rpf': 'barriers', 'p_seating.rpf': 'seating', 'p_hunting.rpf': 'animals',
    'p_carcass.rpf': 'animals', 'mp001_hunting.rpf': 'tools', 'p_window.rpf': 'structures', 'p_debris.rpf': 'rubbish',
    'p_storage.rpf': 'crates', 'p_storage02.rpf': 'crates', 'mp001_storage.rpf': 'crates',
    'mp004_p_storage.rpf': 'crates', 'p_oil_field.rpf': 'crates', 'p_table.rpf': 'tables',
    'mp001_furniture.rpf': 'tables', 'p_lumber.rpf': 'structures', 'p_graveyard.rpf': 'structures',
    'p_armory.rpf': 'firearms', 'p_light_hanging01.rpf': 'lighting', 'p_light_ground01.rpf': 'lighting',
    'p_light_wall01.rpf': 'lighting', 'p_light.rpf': 'lighting', 'p_light_roadside01.rpf': 'lighting',
    'mp005_p_light.rpf': 'lighting', 'p_clothing.rpf': 'clothing',
    'p_clothesline.rpf': 'clothing', 'p_vehicle_static.rpf': 'vehicle',
    'p_plant.rpf': 'plants', 'p_pottery.rpf': 'plants', 'mp001_roadside.rpf': 'structures',
    'mp004_p_roadside.rpf': 'structures', 'p_valuable.rpf': 'loot', 'p_rock_int.rpf': 'nature',
    'p_snow.rpf': 'nature', 'p_luggage.rpf': 'bags', 'p_bathroom.rpf': 'bathroom', 'p_barrier.rpf': 'barriers',
    'p_rooftop.rpf': 'structures', 'mp001_camp.rpf': 'camp', 'mp001_farm.rpf': 'nature',
    # interior
    'int_gunsmith.rpf': 'firearms', 'int_doctor_office.rpf': 'medical', 'int_lootable.rpf': 'storage',
    # structure
    'p_outhouse.rpf': 'structures', 'p_watertower.rpf': 'structures', 'p_stden_cem.rpf': 'structures',
    # vehicle props
    'mp004_gunsforhire.rpf': 'vehicle',
    # level design
    's_minigame.rpf': 'games', 's_posters.rpf': 'signs', 'mp005_s_lev_des_rend_targ.rpf': 'signs',
    's_bullets.rpf': 'firearms', 'mp004_s_bullets.rpf': 'firearms', 'mp005_s_mp_whiskeybottles.rpf': 'food',
    'mp005_s_mp_coins.rpf': 'loot', 'mp005_s_mp_lostjewelry.rpf': 'loot', 'mp005_s_mp_arrowheads.rpf': 'loot',
    'mp005_s_mp_heirlooms.rpf': 'loot', 'rpf_sppack_p_trinkets': 'loot', 'mp005_s_mp_birdeggs.rpf': 'animals',
    'mp005_s_mp_dirtmounds.rpf': 'nature', 'mp005_s_lev_pick.rpf': 'plants', 'mp001_pickups.rpf': 'decor',
}
for _cover in ('bw', 'hdr', 'lag', 'sb', 'sd', 'cwb', 'ch', 'lak', 'tt', 'mt', 'spc', 'ado', 'col', 'cr', 'fm'):
    FIXED['mp005_p_mpcover_%s.rpf' % _cover] = 'barriers'

MIXED = {
    # generic
    'p_household.rpf': 'decor', 'p_store.rpf': 'misc', 'p_camp.rpf': 'camp', 'p_camp02.rpf': 'camp',
    'p_office.rpf': 'office', 'p_tool.rpf': 'tools', 'p_farm.rpf': 'tools', 'p_furniture.rpf': 'storage',
    'p_bedroom.rpf': 'storage', 'p_waterfront.rpf': 'tools', 'p_roadside.rpf': 'structures', 'p_cloth.rpf': 'decor',
    'p_religious.rpf': 'decor', 'p_indian.rpf': 'decor', 'p_mine.rpf': 'tools', 'p_drug.rpf': 'medical',
    'p_instrument.rpf': 'music',
    # vehicle props (a train's dining car has tables)
    'vehicle_props_int.rpf': 'vehicle', 'vehicle_props02.rpf': 'vehicle', 'vehicle_props.rpf': 'vehicle',
    'vehicle_props_mp.rpf': 'vehicle', 'mp005_vehicle_props.rpf': 'vehicle', 'mp001_vehicle_props.rpf': 'vehicle',
    # interior
    'int_general_store.rpf': 'misc', 'int_specialist_shop.rpf': 'decor', 'int_residential.rpf': 'decor',
    'int_saloon.rpf': 'food', 'int_depot.rpf': 'office', 'int_office.rpf': 'office', 'int_hotel.rpf': 'decor',
    'int_barber.rpf': 'bathroom', 'int_jail.rpf': 'misc',
    # structure, urban, areas
    'p_standards.rpf': 'misc', 'p_saloon_01.rpf': 'decor', 'p_new_01.rpf': 'misc', 'p_sha_01.rpf': 'decor',
    # level design
    's_lev_des.rpf': 'misc', 's_cs_objects.rpf': 'misc', 's_cs_objects02.rpf': 'misc', 's_pickups.rpf': 'misc',
    's_set_pieces.rpf': 'misc', 's_lev_des_mission.rpf': 'misc', 's_lev_des_rend_targ.rpf': 'misc',
    'mp005_s_lev_des_mp.rpf': 'misc', 'mp001_lev_des_mp.rpf': 'misc', 's_lev_des_re.rpf': 'misc',
    's_lev_des_skin.rpf': 'misc', 's_lev_des_mp.rpf': 'misc', 'mp005_s_cs_objects.rpf': 'misc',
    'mp005_s_posse_trader.rpf': 'camp', 'mp005_s_posse_bounty.rpf': 'camp', 'mp005_s_posse_collector.rpf': 'camp',
    'mp005_s_possecamp.rpf': 'camp', 'mp004_lev_des_mp.rpf': 'misc', 'mp005_s_lev_des.rpf': 'misc',
    's_caravan.rpf': 'camp', 'rpf_sppack_s_cs_objects': 'misc',
    # where femga could not say (mostly the online updates' props): only p_/s_ names, below
    'unknown': 'misc',
}

VEHICLE_RPF = {'vehicle_props_int.rpf', 'vehicle_props02.rpf', 'vehicle_props.rpf', 'vehicle_props_mp.rpf',
               'mp005_vehicle_props.rpf', 'mp001_vehicle_props.rpf'}

PLANTS_RPF = {'rdr_inst_crops.rpf', 'rdr_flowers.rpf', 'rdr_bushes.rpf', 'rdr_weeds.rpf', 'rdr_grass.rpf',
              'rdr_grass_oldmap.rpf', 'swamp.rpf'}

# Mixed archives (and the unknown one) take only names that read as a prop's: their other names are map pieces
# and shapes ("rec_l6w11_5h4_5z002").
PROP_NAME = re.compile(r'^(mp\d{3}_)?(p|s|prop|i_gen)_[a-z0-9]')

SKIP = re.compile(
    r'(^|_)s?lod\d*(_|$)|slod|_lod|lod_|collision|deleteme|dummy|(^|_)test|test(\d|_|$)|example|(^|_)temp(_|$)'
    r'|_shad(\d|_|$)|proxy|occl|placeholder|decal|vfx|helper|avoidance|bound(s)?\d*$|_interior$|cigcard|cardt_'
    r'|(^|_)des_|^cs_only|_frag(s)?(_|$)|_sim_lod|deadzone|^mp00[5-9]_p_mp_cover|weaponblocker'
)

# A weapon's world model, not a part of one (w_rifle_springfield01, not w_rifle_springfield01_grip2).
WEAPON = re.compile(r'^w_([a-z]+_)?[a-z]+\d*[a-z]?\d*x?$')
WEAPON_PART = re.compile(r'scope|sight|inner|wrap|grip|barrel|clip|stock|hammer\d|cylinder|engrav|strap|sling')

# ---------------------------------------------------------------------------------------------------------------
# Words in a name -> category, first match wins (so "toolbox" is a tool before it is a box).
# ---------------------------------------------------------------------------------------------------------------

KEYWORDS = [
    ('firearms', r'ammo|bullet|cartridge|gun|rifle|revolver|pistol|shotgun|dynamite|holster|bandolier'
                 r'|(?<!b)arrow(?!head)|^w_|powderhorn|gunpowder|quiver|(^|_)bow(\d|_|$)'),
    ('medical', r'medicine|medic|tonic|bandage|syringe|doctor|^p_doc_|(^|_)pill(\d|_|s|$|box|bottle)|apothecar|elixir|reviver|ointment'
                r'|snakeoil|remedy|stimulant|laudanum|potion|healthboost|(^|_)cure|stretcher|horsemed|bitters|firstaid'
                r'|surgical|scalpel|microscope|stethoscope|forceps|tweezer'),
    ('drugs', r'opium|cigar|tobacco|cocaine|chewing|snuff|(^|_)pipe(\d|_|$)|smokingpipe|ashtray|moonshine'
              r'|(^|_)still(\d|_|$)|(^|_)gen_still'),
    ('lighting', r'(?<!c)lamp|(?<!p)lantern|candle|chandelier|(?<!sky)light(?!er|ning|house)|torch|sconce|bulb'),
    ('music', r'banjo|guitar|piano|fiddle(?!_de)|violin|harmonica|accordion|trumpet|cornet|trombone|tuba|(^|_)harp'
              r'|instrument|phonograph|gramophone|musicbox|(^|_)organ|concertina|mandolin|flute|bugle'
              r'|(^|_)drum(\d|_|$|set|kit)|sheetmusic|jawharp'),
    ('games', r'chess|domino|dice|poker|checker|blackjack|roulette|tarot|(^|_)card(s)?(\d|_|$)|game(?!bag)'
              r'|doll(?!ar)|(^|_)toy|puzzle|yoyo|(^|_)kite|fivefinger|knifegame|marble(?!top)'),
    ('loot', r'coin|gold(?!en)|jewel|jewl|necklace|bracelet|brclt|earring|(^|_)ring(\d|_|$|s)|pocketwatch'
             r'|(^|_)watch(\d|_|$)|money|(^|_)cash|billstack|bill_stack|dollar|valuable|treasure|nugget|silver'
             r'|diamond|pearl|(^|_)gem(\d|_|s|$)|trinket|heirloom|brooch|locket|cufflink|strongbox|lockbox'
             r'|(^|_)safe(\d|_|$)|stash|loot|arrowhead|teeth|ivory'),
    ('stunt', r'hurdle|(^|_)ramp|jump'),
    ('barriers', r'fence|barricade|barrier|(^|_)cover(\d|_|comb|$)|sandbag|railing|bollard|barbedwire|blockade'
                 r'|hitch(ing)?(post|po\d)|horsehitch|(^|_)rail(\d|_|s|$)'),
    ('bags', r'(?<!sand)bag(?!uette|pipe|gage)|satchel|suitcase|luggage|baggage|purse|pouch|knapsack|backpack'
             r'|valise|briefcase|haversack|duffel'),
    ('clothing', r'(^|_)hat(s|box|stand|rack|hang|\d|_|$)|hatbox|hatstand|tophat|bowler|boot(?!h|leg)|(?<!horse)shoe'
                 r'|(^|_)coat|coatrack|shirt|(^|_)dress(\d|_|$|form)|glove|bandana|scarf|(^|_)vest(\d|_|$)'
                 r'|trouser|(?<!l)pants|jacket|apron|garment|belt|corset|bonnet|petticoat|neckerchief|poncho'
                 r'|(^|_)spur(\d|_|$)|mannequin|manaquin|tailor|sewing|fabric|clothes|laundry|uniform|cloak'
                 r'|(^|_)mask|(^|_)wig(\d|_|$)|(^|_)cl_|capote|clothing|spinningwheel'),
    ('bathroom', r'(^|_)bath|bathtub|(^|_|wash|bath|dirt)tub(\d|_|$)|toilet|chamberpot|washstand|washbasin|soap'
                 r'|razor|shaving|towel|commode|toothbrush|hairbrush|(^|_)comb(\d|_|$)|perfume|cologne|(^|_)sink'
                 r'|nailfile|barber|grooming|facewash|spittoon'),
    ('seating', r'chair|stool|(?<!work)bench|sofa|settee|couch|rocker|(^|_)pew(\d|_|$)|loveseat|ottoman|throne'
                r'|(^|_)seat|(^|_)swing'),
    ('tables', r'(?<!collec)(?<!loo)table(?!cloth|t)|(^|_)desk|workbench|counter(?!weight)|(^|_)stand(\d|_|$)|pedestal|nightstand'),
    ('beds', r'bed(?!room|side|rock|pan|ding|ford)|(^|_)cot(\d|_|$)|hammock|(^|_)crib(\d|_|$)'
             r'|cradle|bunk|mattress'),
    ('storage', r'armoir|cabinet|dresser|drawer|shelf|shelves|buffet|(^|_)chest(\d|_|$)|wardrobe|cupboard|hutch'
                r'|bookcase|bookshelf|trunk|locker|sideboard|credenza|(^|_)rack(\d|_|$)|(^|_)cubby|coffer'),
    ('crates', r'crate|barrel|(^|_)cask|(^|_)keg|box(\d|_|$|es|set)|(^|_)sack|pallet|carton|cardboard|package'
               r'|parcel|container|(^|_)bale|cottonbale|bundle|basket|bucket|(^|_)pail|(^|_)bin(\d|_|$)'),
    ('electrics', r'generator|telegraph|battery|electric|dynamo|telephone|magneto|switchboard|fusebox|insulator'
                  r'|transformer|turbine|(^|_)motor|engine|machine|boiler|telepole|detector'),
    ('tools', r'hammer|(^|_)saw(\d|_|$|horse|blade|mill|meat)|handsaw|shovel|(^|_)axe|pickaxe|hatchet|(^|_)rake'
              r'|(^|_)hoe(\d|_|$)|wrench|anvil|tool|ladder|wheelbarrow|barrow|(^|_)rope|chain|pulley|broom'
              r'|tongs|crowbar|lockpick|scythe|pitchfork|lasso|shears|scissors|chisel|drill|(^|_)vise|clamp|forge'
              r'|bellows|grindstone|whetstone|sharpening|pliers|screwdriver|(^|_)nail|spade|trowel|sickle|plough'
              r'|(^|_)plow|harness|saddle(?!bag)|bridle|brush(?!wood)|(^|_)(pad)?lock(\d|_|$)|(^|_)key(\d|_|$|ring)'
              r'|spyglass|binocular|camera|compass|magnifying|telescope|lighter|matches|matchbox|winch|hook|bait'
              r'|lure|fishing|(^|_)trap(\d|_|$)|beartrap|knife|machete|(^|_)pole(\d|_|$)|(^|_)oar(\d|_|s|$)'
              r'|anchor|(^|_)net(\d|_|$)|netfish|gauge|pump(?!kin)|sledge|mallet|(^|_)pick(\d|_|$)|brander'
              r'|spinner|spool|scale|grinding|lasso|whip(\d|_|$)|bullwhip|shackle|handcuff|noose|duckcall|(^|_)call(\d|_|$)'),
    ('kitchen', r'stove|oven|kettle|skillet|(^|_)pot(\d|_|s|$)|cookpot|(^|_)pan(\d|_|s|$)|saucepan|plate(?!d)|bowl'
                r'|(^|_)cup(\d|_|s|$)|teacup|(^|_)mug|beermug|(^|_)jug|pitcher|ladle|spoon|(?<!pitch)fork|cutlery'
                r'|utensil|churn|dish|teapot|coffeepot|grinder|cleaver|rollingpin|kitchen|basin|icebox|tray'
                r'|platter|glass(?!es)|tumbler|goblet|canister|(^|_)jar(\d|_|s|$)|(^|_)tin(\d|_|s|$)|mortar|pestle'
                r'|washboard|wringer|(^|_)sieve|colander|funnel|(^|_)ice(box|chest)|(^|_)urn(\d|_|$)|carafe'),
    ('food', r'food|apple|bread|meat|cheese|(?<!cat)fish(?!ing|hook|pole|lure|net|guts)|(^|_)pie(\d|_|s|$)|cake'
             r'|carrot|potato|(^|_)corn(\d|_|$|cob)|beef|pork|(^|_)ham(\d|_|$)|bacon|(^|_)egg(\d|_|s|$)|chicken'
             r'|turkey|steak|(^|_)stew|soup|biscuit|cracker|candy|chocolate|jerky|(^|_)oat|flour|sugar'
             r'|(^|_)salt(\d|_|$)|honey|(^|_)jam(\d|_|$)|fruit|berry|berries|melon|banana|orange|lemon|grape|peach'
             r'|(^|_)pear(\d|_|$)|(^|_)plum|cherry|tomato|lettuce|cabbage|onion|squash|pumpkin|(^|_)bean'
             r'|vegetable|produce|grocery|groceries|bottle|whiskey|whisky|(^|_)beer|wine|(^|_)rum(\d|_|$)'
             r'|(^|_)gin(\d|_|$)|liquor|brandy|bourbon|champagne|absinthe|sherry|cider|coffee|(^|_)tea(\d|_|$)'
             r'|milk|(^|_)water(\d|_|$)|drink|canned|(^|_)can(\d|_|s|$)|cangoods|offal|sausage|pickle|butter'
             r'|(^|_)lard|sandwich|(^|_)feast|(^|_)meal|alcohol|oyster|crab|lobster|(^|_)nut(\d|_|s|$)|walnut'
             r'|peanut|pecan|almond|loaf|baguette|muffin|(^|_)bun(\d|_|s|$)|pudding|(^|_)tart|cookie|sweets'
             r'|(^|_)salmon|trout|(^|_)bass(\d|_|$)|catfish|(^|_)perch|(^|_)pike|crawfish|crawdad|turtlemeat'
             r'|filet|drumstick|(^|_)rib(\d|_|s|$)|(^|_)leg(of|_of)|venison|mutton|(^|_)lamb|(^|_)veal'),
    ('office', r'book(?!case|shelf|end)|paper|letter|ledger|(^|_)pen(\d|_|$)|inkwell|(^|_)ink(\d|_|$|pot)'
               r'|typewriter|twriter|envelope|(^|_)map(\d|_|s|$)|maprolled|twofoldmap|hidemap|document|clipboard'
               r'|newspaper|register|calculator|stamp|quill|(^|_)deed|journal|telegram|notebook|filecabinet'
               r'|blotter|postbox|mailbox|postal|(^|_)mail(\d|_|$)|scroll|certificate|banksealpress|checkemboss'
               r'|(^|_)check(\d|_|$)|receipt|ticket|(^|_)note(\d|_|s|$)|abacus|globe'),
    ('doors', r'door|(^|_)gate(\d|_|$|s)|trapdoor|_gate_'),
    ('signs', r'(?<!de)sign(?!al|et|ature)|poster|billboard|placard|advert|(^|_)notice|(^|_)menu|wanted'),
    ('rugs', r'(?<!d)rug(?!beater)|carpet(?!bag)|(^|_)mat(\d|_|s|$)|doormat'),
    ('decor', r'picture|painting|portrait|photo|statue|(^|_)bust(\d|_|$)|vase|figurine|mirror|clock|ornament'
              r'|trophy|(^|_)flag|banner|curtain|drape|pillow|cushion|tapestry|frame(?!d)|(^|_)art(\d|_|$|work)'
              r'|bookend|sculpture|plaque|fireplace|mantel|fireguard|decor|(^|_)bell(\d|_|$|s)|crucifix|bible'
              r'|idol|totem|dreamcatcher|doily|tablecloth|blanket|quilt|ribbon|bunting|curio|headbust|(^|_)pic_'
              r'|charm|voodoo|incense|(^|_)cross(\d|_|$)|rosary|angel|(^|_)pin(\d|_|$)|badge|medal|feather'),
    ('plants', r'plant|flower|flw|(^|_)fern|cactus|(^|_)herb|ginseng|(^|_|red|desert|blue)sage|yarrow|orchid'
               r'|(^|_)bush|(^|_)weed|(^|_)crop|(^|_)crp_|(^|_)ivy|(^|_)vine|bouquet|wreath|shrub|sapling|planter'
               r'|feverfew|mushroom|chamomile|(^|_)mint|milkweed|lily|lilly|(^|_)rose(\d|_|$)|tulip|daisy|poppy'
               r'|lavender|thistle|clover|(^|_)moss|lichen|(^|_)root|ginger|oregano|thyme|burdock|bitterweed'
               r'|bloodflw|wintergreen|violet|currant|hummingbirdsage|agarita|cotton(?!bale)|tobaccoplant|reed'
               r'|(^|_)saplin'),
    ('animals', r'pelt|carcass|antler|(^|_)hide(\d|_|$|s)|(^|_)fur(\d|_|$)|skull|(^|_)bone(\d|_|s|$)|taxidermy'
                r'|stuffed|(^|_)horn(\d|_|s|$)|tusk|(^|_)claw|fang|talon|(^|_)nest|rabbit|deer|(^|_)bear(\d|_|$|s)'
                r'|wolf|(^|_)elk|buffalo|bison|moose|(^|_)boar|(^|_)fox|cougar|panther|coyote|alligator|turtle'
                r'|snake|(^|_)bird|duck|goose|(^|_)pig(\d|_|$|s)|(^|_)cow(\d|_|$|hide|skull)|sheep|(^|_)goat'
                r'|horse|(^|_)dog(\d|_|$)|(^|_)cat(\d|_|$)|(^|_)rat(\d|_|$|s)|squirrel|beaver|otter|badger|skunk'
                r'|raccoon|possum|armadillo|(^|_)owl|eagle|hawk|(^|_)crow|raven|heron|egret|pelican|vulture'
                r'|condor|frog|(^|_)toad|lizard|gila|insect|beehive|butterfly|spider|scorpion|pronghorn'
                r'|(^|_)ram(\d|_|$)|bighorn|animal|(^|_)guts|fishguts|(^|_)corpse|skeleton|(^|_)skin(\d|_|$|ned)'),
    ('camp', r'(^|_)tent|campfire|(^|_|camp|cook|bon|gen_)fire(\d|_|$|pit|ring|wood)|firewood|cordwood|logpile'
             r'|woodpile|(^|_)tarp|teepee|tipi|(^|_)camp|(^|_)spit(\d|_|$)|(^|_)amb_|(^|_)amb'),
    ('vehicle', r'wagon|(^|_)cart(\d|_|s|$)|coach|(^|_)boat|canoe|(^|_)train|(?<!grinding)(?<!spinning)wheel|buggy|carriage|railcar'
                r'|flatcar|boxcar|caboose|locomotive|handcar|(^|_)raft|(^|_)ship|(^|_)sled|sleigh|bicycle'
                r'|tricycle|velocipede|stroller|(^|_)veh(_|\d)|_veh_|armoredcar|(^|_)car(\d|_|$)|teamster'),
    ('nature', r'(^|_)rock|stone(?!ware)|boulder|(^|_)log(\d|_|s|$|pile)|stump|(^|_)tree|branch|(^|_)snow'
               r'|(^|_)ice(\d|_|$|chunk)|(^|_)dirt|(^|_)mud(\d|_|$)|(^|_)sand(\d|_|$)|gravel|pebble|cliff|driftwood'
               r'|(^|_)twig|(^|_)stick(\d|_|s|$)|(^|_)leaf|leaves|(^|_)hay|haystack|haybale|(^|_)straw(?!berry)'
               r'|grass|(^|_)soil|mound|cave|(^|_)coal|(^|_)ore(\d|_|$)|crystal|geode|fossil|meteor'),
    ('structures', r'(^|_)wall|(^|_)post(\d|_|$)|(^|_)beam|plank|shack|(^|_)shed|(^|_)hut(\d|_|$)|outhouse|tower'
                   r'|bridge|scaffold|stair|(^|_)step(\d|_|s|$)|(^|_)roof|chimney|window|shutter|grave|headstone'
                   r'|tombstone|coffin|(^|_)well(\d|_|$)|trough|windmill|pillar|column|platform|(^|_)dock'
                   r'|(^|_)pier|jetty|skylight|porch|awning|gazebo|gallows|brick|shingle|(^|_)tile|floorboard|lumber'
                   r'|(^|_)board(\d|_|s|$)|(^|_)fort(_|\d)|outpost|scaffolding|signal|watercrane|railroad|telegraphpole'
                   r'|lamppost|flagpole|(^|_)pole|canopy|(^|_)arch(\d|_|$)|monument|memorial|fountain|cistern'),
    ('rubbish', r'trash|garbage|debris|junk|rubble|scrap|broken|litter|(^|_)refuse|waste|(^|_)dung|poop|manure'
                r'|rotten|(^|_|trash|dust)bin(\d|_|$)|(^|_)ash(\d|_|$|es|pile)|ashbucket|(^|_)burnt'),
    ('sports', r'(^|_)ball(\d|_|s|$)|baseball|(^|_)target|boxing|bowling|dumbbell|croquet|horseshoes|archery'
               r'|bullseye|(^|_)racket|weights|(^|_)bat(\d|_|$)|goatball'),
]
KEYWORDS = [(cat, re.compile(rx)) for cat, rx in KEYWORDS]


def keyword_category(name):
    for cat, rx in KEYWORDS:
        if rx.search(name):
            return cat
    return None


def category_of(name, folder, rpf):
    """The category for an object, or None when it does not go in the catalog."""
    if SKIP.search(name):
        return None
    if folder == 'models' and rpf == 'rpf_weapons':
        if not WEAPON.match(name) or WEAPON_PART.search(name):
            return None
        return 'tools' if re.search(r'binocular|camera|detector|lantern|lasso|fishing|kit_|spyglass', name) \
            else 'firearms'
    if folder == 'vegetation':
        if re.search(r'(^|_)dead_|_dead(\d|_|$)', name) and rpf == 'rdr_weeds.rpf':
            return None
        return 'plants' if rpf in PLANTS_RPF else 'nature'
    if rpf in FIXED:
        return FIXED[rpf]
    if rpf in MIXED:
        if not PROP_NAME.match(name):
            return None
        if rpf in VEHICLE_RPF and re.search(r'(^|_)veh(_|\d)', name):
            return 'vehicle'   # a vehicle's load is the vehicle's, whatever it carries ("p_veh_pg_vl_fisherman01x")
        return keyword_category(name) or MIXED[rpf]
    return None


# ---------------------------------------------------------------------------------------------------------------
# Names
# ---------------------------------------------------------------------------------------------------------------

WORDS = """
absinthe accordion acorn adler advert agave alarm album alcohol alligator almond aloe altar amb ambient ammo anchor
angel animal annesburg antler anvil apothecary apple apron arch archery armchair armoir armoire armored army arrow
arrowhead art artichoke artifact ash ashtray awning axe baby back backdrop bacon badge badger bag baggage bait bake
baker balcony bale ball bamboo banana band bandage bandana bandit bandolier banjo bank banner bar barbed barber barge
barn barrel barricade barrier base baseball basin basket bass bat bath bathtub battery bay beam bean bear beard bed
bedroll bee beech beef beehive beer bell bellows belt bench bent berry big bill billboard bills bin binoculars birch
bird biscuit bison bitter bitters black blacksmith blank blanket blind block blood bloody blue blunderbuss board boat
bolt bone bonnet book bookcase bookend books bookshelf boot boots bottle bounty bow bowl bowler box boxes bra brace
bracelet branch brand brander brandy brass bread brick bridge bridle broken broom brush buck bucket buffalo buffet bug
buggy building bulb bull bullet bundle bunk burdock buried burlap burner burnt bush business bust butcher butter cabin
cabinet cable caboose cactus cage cake cal calendar camera camp campfire can candelabra candle candlestick candy cane
canister cannon canoe canopy cap car carafe caravan carcass card cards carriage carrot carrots cart cartridge carving
case cash cask cast cat catfish cattle cave cedar ceiling cellar cello chain chair chalk chamber champagne chandelier
chapel charm check cheese chess chest chick chicken chimney china chip chips chisel chocolate chop chuck church cigar
cigarette clamp claw clay clean cleaver clock closed cloth clothes clothesline clump coal coat coffee coffeepot coffin
coin cold collar collectable collector column comb combined combo comfy compass console container cook cooking cooler
copper cord corn corner corpse corset cot cotton couch cougar counter cover cow coyote crab cracker cradle crane crate
crates crawdad cream crib cross crow crowbar cup cupboard curtain cushion cutter dart dead debris deck decor deer
depot desert desk detail detector device dice dining diorama dirt dirty dish display dock docks doctor doctors dog
doll dollar domino door double dough dove drape drawer dress dresser dressing dried drill drink drum dry duck dummy
dust dutch dynamite eagle egg egret electric elk emerald empty end engine envelope evidence exotic exterior eyes
fabric fallen family fan fancy farm feather fence fern feud fiddle field file filet filing finish fire fireplace
firewood fish fisherman fishing flag flask flat flatbed floor flour flower folded food foot fork fort fountain fox
frame fresh fridge front fruit fur furnace gallows gamble game gang garden garment gas gate gatling gator gauge gear
generator gift gilt gin ginseng glass globe glove goat gold goods goose gourd grain grass grave gravestone green
grinder grinding grocery group guitar gun gunslinger gunsmith hair half hall ham hammer hammock hand handle hang
hanger hanging hare harmonica harness hat hatbox hatchet hawk hay head heart heavy helpwanted herb herbal herbs heron
hide high hitch hitching hold holder hole holster honey hook hoop horn horse horseshoe hose hospital hotel house human
hunter hut ice ind indian ink interact iron ivory jack jacket jail jar jerky jewel jewelry joker jug junk keel keg
kerosene kettle key king kit kitchen knife kudzu ladder ladders ladle lamp lantern large lasso lead leaf leather
leaves ledger leg lemon lens letter lever lid light lime line linen lock locked locker log logo long loot lootable
loupe luggage lumber lure machete machine magnolia mail mallet mansion map maple marble marker mask mat match mattress
meat medal medicine medium melee melon merch metal microscope milk mill mine mirror mission modular mold molotov money
moonshine moonshiner moose mop mortar mount mug musket nail nbd nbx neat neck necklace needle nest net newspaper note
nut oak oar oats office oil old onion open opener opium orange orchid organ ornate outhouse oven owl oxhorn package
pad pail paint painting pallet palm pamphlet pan panel paper parcel parts pass peach pear pedestal pelt pen pepper
perfume pew photo piano pick pickaxe picket pickup picture pie piece pier pig pile pillar pillow pin pine pink pipe
pistol pitcher pitchfork plank plant plate platform plume pocket poker pole ponderosa pony poor poplar porch posse
post poster pot potato pottery pouch powder press privatedining produce prop props puddle pulley pump pumpkin purse
quilt rabbit race rack rag rail railing railroad rake ram ranch rat razor receipt record red refrigerator register
revolver rifle ring roast robbery rock rocker rocking rod roll rolled roof roots rope rose round rubble rug rum sack
saddle safe sage sail salami saloon salt sand sandbag sandwich sandwichboard satchel saucer saw scale scarecrow scarf
scissors scree screen seat set settee sewing shack shackle shady shed sheep shelf shell shield ship shirt shoe shop
shotgun shovel shutter side sign silver single sink skeleton skillet skin skull skylight sled sledge sleeper slept
slice slop small smith smoke snake soap sofa soup spade specimen spike spinning spittoon split spool spoon spring
stable stack stage stagecoach stair stairs stake stalks stall stamp stand standing stash static station statue steak
steam step stew stick still stockade stocking stone stones stool storage store stove strap straw street string strip
strong strongbox stump suffragette sugar suit suitcase supplies supply swamp swing sword table tack tail tailor tall
tank tap tar target taxidermy tea teapot telegraph telescope tent theater thin throw tin tobacco toilet tomahawk
tomato tomb tongs tool toolbox tools tooth top torch towel tower toy track trade trader tradesman train trap traveling
tray tree tress trimmed trinket trolley trophy troub trough trout trunk tub turkey turtle twine typewriter umbrella
unburied used vase vault vest vice victorian violin wagon wall wardrobe wash washtub watch water watermelon wax
waxdrip wedge weed well whale wheat wheel wheelbarrow whip whiskey white whittling wicker wild windmill window wine
winter wire wolf wood wooden work workbench wreath xlarge yarn yarrow
"""
VOCAB = set(WORDS.split())
RESIDUE = collections.Counter()


def split_words(token):
    """Split a run of letters into WORDS (fewest pieces, unknown letters cost most); unknown runs stay whole. A scrap of
    fewer than five letters no word explains never splits off, and a three-letter word costs more, so "mattress" stays
    whole rather than "mat tress"."""
    n = len(token)
    cost = [0] + [None] * n
    back = [None] * (n + 1)
    for i in range(n):
        if cost[i] is None:
            continue
        for j in range(i + 1, n + 1):
            w = token[i:j]
            if w in VOCAB:
                c = cost[i] + (1 if len(w) >= 4 else 2)
            elif j - i >= 5 or (i == 0 and j == n):
                c = cost[i] + 4 + 0.6 * (j - i)
            else:
                continue
            if cost[j] is None or c < cost[j]:
                cost[j] = c
                back[j] = i
    pieces, j = [], n
    while j > 0:
        i = back[j]
        pieces.append(token[i:j])
        j = i
    pieces.reverse()
    out = []
    for w in pieces:
        known = w in VOCAB
        if not known and out and not out[-1][1]:
            out[-1] = (out[-1][0] + w, False)
        else:
            out.append((w, known))
    for w, known in out:
        if not known and len(w) > 3:
            RESIDUE[w] += 1
    return [w for w, _ in out]


PREFIX = re.compile(r'^(mp\d{3}_|dne_)?((p|s|prop|i|w)_)?((cs|gen|inv|mp|int|grp|group|sto|new|dis)_)?')


SAY = {'amb': '', 'nbx': 'Saint Denis', 'nbd': 'Saint Denis'}   # ambient; Saint Denis' two codes


def display_name(model):
    rest = PREFIX.sub('', model) or model
    words = []
    for part in rest.split('_'):
        for run in re.findall(r'[a-z]+|\d+', part):
            if run.isdigit():
                words.append(run)
            elif words and words[-1].isdigit() and len(run) <= 2:
                # 01x, 01ax, 02b: the variant's letter stays with its number, a trailing x goes
                letter = run[:-1] if run.endswith('x') else run
                if letter:
                    words[-1] += letter
            elif run == 'x':
                continue
            else:
                for w in split_words(run):
                    w = SAY.get(w, w)
                    if w:
                        words.append(w)
    name = ' '.join(words).strip() or model
    name = name[0].upper() + name[1:]
    return name[:64]


# ---------------------------------------------------------------------------------------------------------------

def lua_str(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'") + "'"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if len(args) != 1:
        sys.exit('usage: python -I dev/prop_catalog_rdr.py <object_list.lua> [--stats] [--residue]')
    rows, seen, nospawn, dropped = [], set(), read_nospawn(), 0
    with open(args[0], encoding='utf-8', errors='replace') as f:
        for line in f:
            m = LINE.match(line)
            if not m:
                continue
            name, folder, rpf = m.group(2).lower(), m.group(4), m.group(5)
            if name in seen or not re.match(r'^[a-z0-9_]+$', name) or len(name) > 80:
                continue
            cat = category_of(name, folder, rpf)
            if cat is None:
                continue
            seen.add(name)
            if name in nospawn:
                dropped += 1
                continue
            rows.append((name, cat, display_name(name)))
    rows.sort(key=lambda r: (r[1], r[0]))

    if '--stats' in sys.argv:
        by = collections.defaultdict(list)
        for r in rows:
            by[r[1]].append(r)
        for cat in sorted(by, key=lambda c: -len(by[c])):
            ex = by[cat][::max(1, len(by[cat]) // 12)][:12]
            print('%-10s %5d  %s' % (cat, len(by[cat]), ', '.join('%s=%s' % (r[0], r[2]) for r in ex)))
        print('total', len(rows))
    if '--residue' in sys.argv:
        print(', '.join('%s %d' % kv for kv in RESIDUE.most_common(200)))
    if '--stats' in sys.argv or '--residue' in sys.argv:
        return

    out = [
        '-- The furniture catalog that ships with spur_core: every prop the furnisher offers out of the box.',
        '--',
        '-- RedM (spur_core, 24 Nov 2026): RDR2\'s props, %d of them, made by dev/prop_catalog_rdr.py from femga\'s' % len(rows),
        '-- object list (github.com/femga/rdr3_discoveries, objects/object_list.lua). whip_core\'s list was the original game\'s and',
        '-- none of it exists in RDR2 (migration 048_redm_prop_seed_emptied takes it out of a database seeded with it). The',
        '-- categories and names are guessed from each model\'s archive and the words in its name: a wrong one is one',
        '-- /prop add <category> away, and /prop remove takes a prop out for good. Do not edit by hand: run the script.',
        '--',
        '-- Each line is { model, category, name }, category one of Config.PropCategories\' keys. The server copies these',
        '-- into the prop_catalog table the first time it sees each model, so this file only ever ADDS props: a row once',
        '-- seeded keeps its category and name (migration 050_redm_rdr_prop_seed_fixes re-filed the first seed\'s once).',
        '-- A name the game does not have costs nothing: the furnisher hides it and an admin\'s client reports it. Those',
        '-- /propcheck found the game will not spawn (%d, nearly all doors and gates) are left out:' % dropped,
        '-- dev/prop_catalog_rdr_nospawn.txt.',
        '',
        'PropCatalogSeed = {',
    ]
    for model, cat, name in rows:
        out.append('    { %s, %s, %s },' % (lua_str(model), lua_str(cat), lua_str(name)))
    out.append('}')
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(out) + '\n')
    print('wrote %d props to %s (%d left out: %s)' % (len(rows), os.path.normpath(OUT), dropped,
                                                      os.path.basename(NOSPAWN)))


if __name__ == '__main__':
    main()
