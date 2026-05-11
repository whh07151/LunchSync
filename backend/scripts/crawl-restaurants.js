"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
const supabase_js_1 = require("@supabase/supabase-js");
const dotenv = __importStar(require("dotenv"));
dotenv.config();
const KAKAO_REST_API_KEY = process.env.KAKAO_REST_API_KEY;
const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!KAKAO_REST_API_KEY || !SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    console.error('필수 환경 변수가 없습니다. .env 파일을 확인하세요.');
    console.error('필요: KAKAO_REST_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY');
    process.exit(1);
}
const supabase = (0, supabase_js_1.createClient)(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
async function searchKakaoPlaces(lat, lng, radius) {
    const allPlaces = [];
    for (let page = 1; page <= 3; page++) {
        const url = new URL('https://dapi.kakao.com/v2/local/search/category.json');
        url.searchParams.set('category_group_code', 'FD6');
        url.searchParams.set('x', lng.toString());
        url.searchParams.set('y', lat.toString());
        url.searchParams.set('radius', radius.toString());
        url.searchParams.set('sort', 'distance');
        url.searchParams.set('size', '15');
        url.searchParams.set('page', page.toString());
        const res = await fetch(url.toString(), {
            headers: { Authorization: `KakaoAK ${KAKAO_REST_API_KEY}` },
        });
        if (!res.ok) {
            console.error(`카카오 API 에러: ${res.status}`);
            break;
        }
        const data = await res.json();
        allPlaces.push(...(data.documents || []));
        if (data.meta?.is_end)
            break;
    }
    return allPlaces;
}
async function fetchNaverDetail(placeName) {
    try {
        const searchUrl = `https://map.naver.com/p/api/search/allSearch?query=${encodeURIComponent(placeName)}&type=all`;
        const searchRes = await fetch(searchUrl, {
            headers: {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                Referer: 'https://map.naver.com/',
            },
        });
        if (!searchRes.ok)
            return null;
        const searchData = await searchRes.json();
        const placeList = searchData?.result?.place?.list;
        if (!placeList || placeList.length === 0)
            return null;
        const firstPlace = placeList[0];
        const placeId = firstPlace.id;
        const menuUrl = `https://pcmap-api.place.naver.com/place/rest/restaurant/${placeId}/menu`;
        const menuRes = await fetch(menuUrl, {
            headers: {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                Referer: 'https://pcmap.place.naver.com/',
            },
        });
        let menus = [];
        if (menuRes.ok) {
            const menuData = await menuRes.json();
            const rawMenus = menuData?.menus || menuData?.menuItems || [];
            menus = rawMenus
                .filter((m) => m.name && m.price)
                .map((m) => ({
                name: String(m.name).trim(),
                price: parsePrice(m.price),
                description: m.description || '',
                imageUrl: m.imageUrl || m.images?.[0] || null,
            }))
                .filter((m) => m.price > 0)
                .slice(0, 20);
        }
        return {
            rating: parseFloat(firstPlace.reviewScore) || 0,
            reviewCount: parseInt(firstPlace.reviewCount) || 0,
            menus,
        };
    }
    catch {
        return null;
    }
}
function parsePrice(priceStr) {
    if (typeof priceStr === 'number')
        return priceStr;
    if (typeof priceStr !== 'string')
        return 0;
    return parseInt(priceStr.replace(/[^0-9]/g, '')) || 0;
}
function mapCategory(kakaoCategory) {
    const cat = kakaoCategory.toLowerCase();
    if (cat.includes('한식'))
        return '한식';
    if (cat.includes('중식') || cat.includes('중국'))
        return '중식';
    if (cat.includes('일식') || cat.includes('일본'))
        return '일식';
    if (cat.includes('양식'))
        return '양식';
    if (cat.includes('분식'))
        return '분식';
    if (cat.includes('카페'))
        return '카페';
    if (cat.includes('패스트') || cat.includes('치킨'))
        return '패스트푸드';
    return '기타';
}
function mapMenuCategory(menuName) {
    const name = menuName.toLowerCase();
    if (name.includes('밥') || name.includes('덮밥'))
        return 'rice';
    if (name.includes('면') || name.includes('국수') || name.includes('파스타'))
        return 'noodle';
    if (name.includes('음료') || name.includes('커피'))
        return 'drink';
    if (name.includes('떡볶이') || name.includes('튀김'))
        return 'snack';
    return 'main';
}
function delay(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}
async function main() {
    const args = process.argv.slice(2);
    if (args.length < 2) {
        console.log('사용법: npx ts-node scripts/crawl-restaurants.ts <위도> <경도> [반경m]');
        console.log('예시:   npx ts-node scripts/crawl-restaurants.ts 37.4979 127.0276 1000');
        process.exit(1);
    }
    const lat = parseFloat(args[0]);
    const lng = parseFloat(args[1]);
    const radius = parseInt(args[2]) || 1000;
    console.log(`\n🔍 크롤링 시작: 위도=${lat}, 경도=${lng}, 반경=${radius}m\n`);
    const places = await searchKakaoPlaces(lat, lng, radius);
    console.log(`📍 카카오 검색 결과: ${places.length}개 식당\n`);
    let saved = 0;
    let totalMenus = 0;
    for (const place of places) {
        process.stdout.write(`  ${place.place_name} ... `);
        const detail = await fetchNaverDetail(place.place_name);
        await delay(1000);
        const category = mapCategory(place.category_name);
        const menus = detail?.menus || [];
        const avgPrice = menus.length > 0
            ? Math.round(menus.reduce((s, m) => s + m.price, 0) / menus.length)
            : 0;
        const restaurantData = {
            name: place.place_name,
            category,
            address: place.road_address_name || place.address_name,
            lat: parseFloat(place.y),
            lng: parseFloat(place.x),
            price_range: avgPrice > 0 ? Math.round(avgPrice / 1000) : 2,
        };
        const { data: existing } = await supabase
            .from('restaurants')
            .select('id')
            .eq('name', restaurantData.name)
            .eq('address', restaurantData.address)
            .limit(1);
        let restaurantId;
        if (existing && existing.length > 0) {
            restaurantId = existing[0].id;
            await supabase.from('restaurants').update(restaurantData).eq('id', restaurantId);
        }
        else {
            const { data: inserted, error } = await supabase
                .from('restaurants')
                .insert(restaurantData)
                .select('id')
                .single();
            if (error || !inserted) {
                console.log(`❌ 저장 실패`);
                continue;
            }
            restaurantId = inserted.id;
        }
        if (menus.length > 0) {
            await supabase.from('menu_items').delete().eq('restaurant_id', restaurantId);
            const menuRows = menus.map((m) => ({
                restaurant_id: restaurantId,
                name: m.name,
                price: m.price,
                category: mapMenuCategory(m.name),
                description: m.description,
                image_url: m.imageUrl || null,
            }));
            await supabase.from('menu_items').insert(menuRows);
        }
        saved++;
        totalMenus += menus.length;
        console.log(`✅ 메뉴 ${menus.length}개`);
    }
    console.log(`\n📊 결과: ${saved}/${places.length}개 식당 저장, 총 ${totalMenus}개 메뉴\n`);
}
main().catch(console.error);
//# sourceMappingURL=crawl-restaurants.js.map