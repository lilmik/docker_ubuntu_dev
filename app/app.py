# 使用Uvicorn 在 3000 端口启动服务的命令
# python app.py --port 3000

# 显式指定3000端口,进入开发模式
# python app.py --dev --port 3000  

from flask import Flask, render_template_string
import argparse
from fastapi import FastAPI
from starlette.middleware.wsgi import WSGIMiddleware
import uvicorn

app = Flask('dynamic_patterns')

HTML_TEMPLATE = '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>动态复杂图案生成器</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link href="https://cdn.jsdelivr.net/npm/font-awesome@4.7.0/css/font-awesome.min.css" rel="stylesheet">
    <script>
        tailwind.config = {
            theme: {
                extend: {
                    colors: {
                        primary: '#3B82F6',
                        secondary: '#8B5CF6',
                        accent: '#EC4899',
                    },
                    fontFamily: {
                        sans: ['Inter', 'system-ui', 'sans-serif'],
                    },
                }
            }
        }
    </script>
    <style type="text/tailwindcss">
        @layer utilities {
            .pattern-container {
                @apply fixed inset-0 overflow-hidden pointer-events-none;
            }
            .pattern {
                @apply absolute transition-all duration-1000 ease-in-out;
                will-change: transform, opacity;
            }
            .shape-circle { border-radius: 50%; }
            .shape-square { border-radius: 0; }
            .shape-rectangle { border-radius: 0; }
            .shape-diamond { border-radius: 0; }
            .shape-triangle {
                border-radius: 0;
                clip-path: polygon(50% 0%, 0% 100%, 100% 100%);
            }
        }
    </style>
    <style>
        body { background-color: #0F172A; margin: 0; padding: 0; }
        .shape-pentagon {
            clip-path: polygon(50% 0%, 100% 38%, 82% 100%, 18% 100%, 0% 38%);
        }
        .shape-hexagon {
            clip-path: polygon(25% 0%, 75% 0%, 100% 50%, 75% 100%, 25% 100%, 0% 50%);
        }
        .shape-star {
            clip-path: polygon(50% 0%, 61% 35%, 98% 35%, 68% 57%, 79% 91%, 50% 70%, 21% 91%, 32% 57%, 2% 35%, 39% 35%);
        }
        @supports not (clip-path: polygon(50% 0%, 61% 35%, 98% 35%)) {
            .shape-star {
                background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'%3E%3Cpath d='M50,0 L61,35 L98,35 L68,57 L79,91 L50,70 L21,91 L32,57 L2,35 L39,35 Z' fill='currentColor'/%3E%3C/svg%3E");
                background-size: contain;
                background-repeat: no-repeat;
                background-position: center;
                background-color: transparent !important;
            }
        }
    </style>
</head>
<body class="min-h-screen">
    <div class="relative z-10 flex items-center justify-center min-h-screen p-4">
        <div class="text-center text-white">
            <h1 class="text-[clamp(2rem,5vw,4rem)] font-bold mb-4 bg-clip-text text-transparent bg-gradient-to-r from-primary to-accent">
                动态复杂图案生成器
            </h1>
            <p class="text-xl mb-8 text-gray-300 max-w-2xl mx-auto">
                随机生成各种形状和颜色的图案，包括圆形、方形、三角形、长方形、菱形、五边形、六边形和五角星
            </p>
            <div class="flex flex-wrap justify-center gap-4">
                <button id="moreBtn" class="bg-primary hover:bg-primary/80 text-white font-bold py-2 px-6 rounded-full transition-all transform hover:scale-105 flex items-center gap-2">
                    <i class="fa fa-plus"></i> 更多图案
                </button>
                <button id="clearBtn" class="bg-gray-700 hover:bg-gray-600 text-white font-bold py-2 px-6 rounded-full transition-all transform hover:scale-105 flex items-center gap-2">
                    <i class="fa fa-trash"></i> 清除所有
                </button>
                <button id="infoBtn" class="bg-secondary hover:bg-secondary/80 text-white font-bold py-2 px-6 rounded-full transition-all transform hover:scale-105 flex items-center gap-2">
                    <i class="fa fa-info"></i> 形状说明
                </button>
            </div>
            
            <!-- 形状说明弹窗 -->
            <div id="infoModal" class="fixed inset-0 bg-black/70 z-50 flex items-center justify-center p-4 hidden">
                <div class="bg-gray-800 rounded-xl p-6 max-w-md w-full text-left">
                    <h3 class="text-2xl font-bold mb-4 text-white">可用形状</h3>
                    <ul class="text-gray-300 space-y-2">
                        <li><i class="fa fa-circle text-primary mr-2"></i>圆形</li>
                        <li><i class="fa fa-square text-primary mr-2"></i>正方形</li>
                        <li><i class="fa fa-rectangle-wide text-primary mr-2"></i>长方形</li>
                        <li><i class="fa fa-diamond text-primary mr-2"></i>菱形</li>
                        <li><i class="fa fa-caret-up text-primary mr-2 transform rotate-45"></i>三角形</li>
                        <li><i class="fa fa-star text-primary mr-2"></i>五角星</li>
                        <li><i class="fa fa-stop text-primary mr-2"></i>五边形</li>
                        <li><i class="fa fa-hexagon text-primary mr-2"></i>六边形</li>
                    </ul>
                    <button id="closeInfoBtn" class="mt-6 bg-primary text-white px-4 py-2 rounded-lg">关闭</button>
                </div>
            </div>
        </div>
    </div>
    
    <!-- 图案容器 -->
    <div id="patternContainer" class="pattern-container"></div>

    <script>
        const colors = [
            '#3B82F6', '#8B5CF6', '#EC4899', '#10B981', '#F59E0B',
            '#EF4444', '#6366F1', '#14B8A6', '#F43F5E', '#84CC16',
            '#60A5FA', '#A78BFA', '#F9A8D4', '#34D399', '#FBBF24',
            '#F87171', '#818CF8', '#2DD4BF', '#FB7185', '#A3E635'
        ];
        const shapes = ['circle','square','rectangle','diamond','triangle','pentagon','hexagon','star'];
        function random(min, max) { return Math.random() * (max - min) + min; }
        function getRandomColor() { return colors[Math.floor(Math.random() * colors.length)]; }
        function getRandomShape() { return shapes[Math.floor(Math.random() * shapes.length)]; }
        function createPattern() {
            const container = document.getElementById('patternContainer');
            if (!container) return;
            const pattern = document.createElement('div');
            const shape = getRandomShape();
            const color = getRandomColor();
            const opacity = random(0.3, 0.8);
            const x = random(8, 92);
            const y = random(8, 92);
            const rotation = random(0, 360);
            let width, height;
            switch(shape) {
                case 'circle':
                case 'square':
                case 'pentagon':
                case 'hexagon':
                case 'star':
                    const size = random(20, 120);
                    width = size; height = size; break;
                case 'rectangle':
                    width = random(40, 180); height = random(20, 80); break;
                case 'diamond':
                case 'triangle':
                    width = random(30, 150); height = width; break;
                default:
                    width = random(30, 100); height = width;
            }
            pattern.className = `pattern shape-${shape}`;
            pattern.style.width = `${width}px`;
            pattern.style.height = `${height}px`;
            pattern.style.backgroundColor = color;
            pattern.style.opacity = '0';
            pattern.style.left = `${x}%`;
            pattern.style.top = `${y}%`;
            let transform = `translate(-50%, -50%) rotate(${rotation}deg)`;
            if (shape === 'diamond') transform = `translate(-50%, -50%) rotate(${rotation + 45}deg)`;
            pattern.style.transform = transform;
            container.appendChild(pattern);
            void pattern.offsetWidth;
            setTimeout(() => { pattern.style.opacity = opacity.toString(); }, 50);
            const lifeTime = random(4000, 12000);
            setTimeout(() => {
                pattern.style.opacity = '0';
                pattern.style.transform = `${transform} scale(0.5)`;
                setTimeout(() => {
                    if (container.contains(pattern)) container.removeChild(pattern);
                }, 1000);
            }, lifeTime);
            return pattern;
        }
        function startAutoGeneration() {
            setInterval(() => {
                const container = document.getElementById('patternContainer');
                if (container && document.querySelectorAll('.pattern').length < 60) {
                    createPattern();
                }
            }, 400);
        }
        document.addEventListener('DOMContentLoaded', () => {
            const moreBtn = document.getElementById('moreBtn');
            const clearBtn = document.getElementById('clearBtn');
            const infoBtn = document.getElementById('infoBtn');
            const infoModal = document.getElementById('infoModal');
            const closeInfoBtn = document.getElementById('closeInfoBtn');
            if (moreBtn) moreBtn.addEventListener('click', () => { for (let i = 0; i < 12; i++) setTimeout(() => createPattern(), i * 100); });
            if (clearBtn) clearBtn.addEventListener('click', () => {
                const patterns = document.querySelectorAll('.pattern');
                patterns.forEach((pattern, index) => {
                    setTimeout(() => {
                        pattern.style.opacity = '0';
                        pattern.style.transform = `${pattern.style.transform} scale(0.5)`;
                        setTimeout(() => { if (pattern.parentNode) pattern.parentNode.removeChild(pattern); }, 500);
                    }, index * 50);
                });
            });
            if (infoBtn && infoModal && closeInfoBtn) {
                infoBtn.addEventListener('click', () => infoModal.classList.remove('hidden'));
                closeInfoBtn.addEventListener('click', () => infoModal.classList.add('hidden'));
                infoModal.addEventListener('click', (e) => { if (e.target === infoModal) infoModal.classList.add('hidden'); });
            }
            startAutoGeneration();
        });
    </script>
</body>
</html>
'''

@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE)


def run_with_uvicorn(port=3000):
    """使用 Uvicorn 启动生产级服务器"""
    fastapi_app = FastAPI()
    fastapi_app.mount("/", WSGIMiddleware(app))
    uvicorn.run(fastapi_app, host="0.0.0.0", port=port, log_level="info")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='动态复杂图案Web应用')
    parser.add_argument('--port', type=int, default=3000, help='指定Web服务端口，默认3000')
    parser.add_argument('--dev', action='store_true', help='使用开发服务器（默认使用Uvicorn）')
    args = parser.parse_args()

    if args.dev:
        app.run(host='0.0.0.0', port=args.port, debug=False)
    else:
        run_with_uvicorn(args.port)
