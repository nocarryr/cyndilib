from __future__ import annotations
from pathlib import Path

PROJECT_PATH = Path(__file__).resolve().parent

class AnnotateIndex(object):
    def __init__(
        self,
        package_name: str,
        parent: 'AnnotateIndex'|None = None,
        root_dir: Path|None = None,
        out_dir: Path|None = None,
    ):
        self.parent = parent
        if root_dir is not None and parent is not None:
            raise ValueError('only root object can have root_dir')
        self._root_dir = root_dir

        self.modules = set()
        self.children = {}
        if '.' in package_name:
            self.package_name = package_name.split('.')[0]
            self.add_package(package_name)
        else:
            self.package_name = package_name
        self._out_dir = out_dir
    @property
    def root(self):
        p = self.parent
        if p is None:
            return self
        return p.root
    @property
    def root_dir(self) -> Path|None:
        if self.parent is None:
            p = self._root_dir
            if p is None:
                p = PROJECT_PATH
            return p
        return self.parent.root_dir
    @property
    def out_dir(self) -> Path:
        p = self._out_dir
        if p is None:
            if self.parent is None:
                return self.root_dir
            fqdn = self.fqdn.split('.')
            p = self._out_dir = self.root_dir.joinpath(*fqdn)
        return p
    @property
    def fqdn(self):
        p = self.parent
        if p is None:
            return self.package_name
        fqdn = p.fqdn
        if not len(fqdn):
            return self.package_name
        return '{}.{}'.format(fqdn, self.package_name)
    def build_href(self, name: str|None = None, relative_to: 'AnnotateIndex'|None = None) -> str:
        fn = self.to_path(name)
        if relative_to is not None:
            fn = fn.relative_to(relative_to.out_dir)
        else:
            fn = fn.relative_to(self.root_dir)
        return str(fn)
    def to_path(self, name=None):
        p = self.out_dir
        if name is not None:
            p = p / name
        return p
    def find(self, module_name):
        return self.root.find_relative(module_name)
    def find_relative(self, module_name):
        m = module_name.split('.')
        if self.parent is not None and len(self.package_name):
            if m[0] != self.package_name:
                return None
            m = m[1:]
            if not len(m):
                return self
        c = self.children.get(m[0])
        if c is not None:
            return c.find_relative('.'.join(m))
        if len(m) == 1 and m[0] in self.modules:
            return m[0]
        return None
    def add_package(self, package_name):
        pkg = package_name.split('.')
        if self.parent is not None and len(self.package_name):
            assert pkg[0] == self.package_name
            pkg = pkg[1:]
            if not len(pkg):
                return self
        c = self.children.get(pkg[0])
        if c is not None:
            return c.add_package('.'.join(pkg))
        c = AnnotateIndex('.'.join(pkg), self)
        self.children[c.package_name] = c
        return c.find_relative('.'.join(pkg))
    def add_module(self, module_name):
        m = module_name.split('.')
        if self.parent is not None and len(self.package_name):
            assert m[0] == self.package_name
            m = m[1:]
            assert len(m) > 0
            if len(m) == 1:
                self.modules.add(m[0])
                return self
        package_name = '.'.join(module_name.split('.')[:-1])
        self.add_package(package_name)
        pkg = self.find_relative(package_name)
        if pkg is None:
            print(f'{self=}, {module_name=}, {package_name=}')
        pkg.add_module('.'.join([pkg.package_name, module_name.split('.')[-1]]))
        return pkg
    def walk(self):
        yield self
        for key in sorted(self.children.keys()):
            c = self.children[key]
            yield from c.walk()
    def build_html(self):
        doc = ['<html><body><ul>']
        li_fmt = '<li><a href={href}>{name}</a></li>'
        if self.parent is not None:
            doc.append(li_fmt.format(href='../index.html', name='..'))
        for key in sorted(self.children.keys()):
            c = self.children[key]
            doc.extend(c.html_list_item(relative_to=self))
        for module_name in sorted(self.modules):
            href = '{}.html'.format(module_name)
            doc.append(li_fmt.format(href=href, name='{}.pyx'.format(module_name)))
        doc.append('</ul></body></html>')
        return '\n'.join(doc)
    def html_list_item(self, relative_to=None):
        li_fmt = '<li><a href={href}>{name}</a></li>'
        href = self.build_href('index.html', relative_to)
        doc = [
            '<li><a href={}>{}</a>'.format(href, self.package_name),
            '<ul>'
        ]
        for key in sorted(self.children.keys()):
            c = self.children[key]
            doc.extend(c.html_list_item(relative_to))
        for module_name in sorted(self.modules):
            href = self.build_href('{}.html'.format(module_name), relative_to)
            doc.append(li_fmt.format(href=href, name='{}.pyx'.format(module_name)))
        doc.append('</ul></li>')
        return doc
    def write_html(self):
        filename = self.out_dir / 'index.html'
        html = self.build_html()
        filename.write_text(html)
    def __repr__(self):
        return '<{self.__class__}({self})>'.format(self=self)
    def __str__(self):
        return self.fqdn
